;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(in-package #:ultimate-tic-tac-toe.web)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (pushnew "hx-" spinneret:*unvalidated-attribute-prefixes* :test #'string=))

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

(defparameter *room-repository* (make-memory-room-repository))

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
  (destructuring-bind (status headers body) response
    (list status
          (append headers
                  (missing-default-headers headers *security-headers*))
          body)))

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

(defun emit-csrf-input ()
  (let ((token (current-csrf-token)))
    (when token
      (spinneret:with-html
        (:input :type "hidden"
                :name "csrf-token"
                :value token)))))

(defmacro with-game-post-form ((path &rest attributes) &body body)
  `(spinneret:with-html
     (:form ,@attributes
            :method "post"
            :action ,path
            :hx-post ,path
            :hx-target "#game"
            :hx-swap "outerHTML"
       (emit-csrf-input)
       ,@body)))

(defmacro with-room-post-form ((path &rest attributes) &body body)
  `(spinneret:with-html
     (:form ,@attributes
            :method "post"
            :action ,path
            :hx-post ,path
            :hx-target "#room-game"
            :hx-swap "outerHTML"
       (emit-csrf-input)
       ,@body)))

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

(defun form-parameter (params name)
  (cdr (assoc name params :test #'string=)))

(defun form-submitted-p (params &rest names)
  (some (lambda (name)
          (assoc name params :test #'string=))
        names))

(defun csrf-parameter-valid-p (params)
  (csrf-token-valid-p (form-parameter params "csrf-token")))

(defun route-parameter (params key)
  (cdr (assoc key params :test #'eql)))

(defun room-path (code)
  (format nil "/rooms/~A" code))

(defun room-game-path (code)
  (format nil "/rooms/~A/game" code))

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

(defun respond-after-post (game &key notice)
  (if (htmx-request-p)
      (html-response (render-htmx-response game :notice notice))
      (progn
        (remember-notice notice)
        (redirect-response "/"))))

(defun parse-index (value)
  (when value
    (handler-case
        (parse-integer value :junk-allowed nil)
      (error () nil))))

(defun move-rejection-notice (rejection)
  (ecase (move-rejected-reason rejection)
    ((:invalid-board :invalid-cell)
     "That move was not understood.")
    (:game-over
     "The game is already over.")
    (:closed-board
     "That board is already complete.")
    (:wrong-board
     "That move belongs in the target board.")
    (:occupied-cell
     "That square is no longer available.")))

(defun computer-turn-p (game)
  (and (not (game-over-p game))
       (eql (session-computer-player)
            (game-next-player game))))

(defun maybe-play-computer-turn (game)
  (when (computer-turn-p game)
    (ecase (session-opponent-mode)
      (:easy (play-first-legal-move game))
      (:normal (play-best-tactical-move game))
      (:hard (play-best-strategic-move game))))
  game)

(defun mark-asset (mark)
  (ecase mark
    (:x "/x.svg")
    (:o "/o.svg")))

(defun board-position-label (board)
  (aref *board-position-labels* board))

(defun grid-position-aria-label (position)
  (string-downcase (board-position-label position)))

(defun target-label (game)
  (cond
    ((game-winner game) "Done")
    ((game-active-board game)
     (format nil "~A board" (board-position-label (game-active-board game))))
    (t "Any open board")))

(defun result-label (game)
  (ecase (game-winner game)
    (:x (format nil "~A wins!" (player-name :x)))
    (:o (format nil "~A wins!" (player-name :o)))
    (:draw "Draw game")
    ((nil) (format nil "~A to move"
                   (player-name (game-next-player game))))))

(defun global-winning-board-p (game board)
  (member board
          (winning-line-positions (global-winning-line game))
          :test #'=))

(defun cell-aria-label (game board cell)
  (format nil "Play ~A in the ~A board, ~A square"
          (player-name (game-next-player game))
          (grid-position-aria-label board)
          (grid-position-aria-label cell)))

(defun emit-mark (mark)
  (spinneret:with-html
    (:img :class (css-classes "mark"
                              (format nil "mark-~(~A~)" mark))
          :src (mark-asset mark)
          :alt (player-label mark))))

(defun emit-cell (game board cell)
  (let ((mark (mark-at game board cell))
        (legal-p (legal-move-p game board cell)))
    (spinneret:with-html
      (:div :class (css-classes "micro-cell"
                                (when mark "is-filled")
                                (when legal-p "is-playable"))
        (cond
          (mark
           (emit-mark mark))
          (legal-p
           (with-game-post-form (*current-game-moves-path* :class "cell-form")
             (:input :type "hidden"
                     :name "board"
                     :value board)
             (:input :type "hidden"
                     :name "cell"
                     :value cell)
             (:button :class "cell-button"
                      :type "submit"
                      :aria-label (cell-aria-label game board cell)
               (:span :class "cell-dot"
                      :aria-hidden "true"))))
          (t
           (spinneret:with-html
             (:span :class "cell-blank"
                    :aria-hidden "true"))))))))

(defun emit-local-board (game board)
  (let* ((outcome (board-outcome game board))
         (available-p (available-board-p game board))
         (active-board (game-active-board game))
         (active-p (and active-board (= board active-board))))
    (spinneret:with-html
      (:section :class (css-classes "local-board"
                                    (when available-p "is-available")
                                    (when (and available-p (null active-board))
                                      "is-choice")
                                    (when active-p "is-active")
                                    (when (eql outcome :x) "is-won-x")
                                    (when (eql outcome :o) "is-won-o")
                                    (when (eql outcome :draw) "is-draw")
                                    (when (global-winning-board-p game board)
                                      "is-global-win-board"))
                :aria-label (format nil "Board ~D, ~A"
                                    (1+ board)
                                    (outcome-label outcome))
        (:div :class "micro-grid"
          (loop for cell below +board-count+
                do (emit-cell game board cell))
          (when (player-p outcome)
            (spinneret:with-html
              (:img :class (css-classes "board-win-glyph"
                                        (when (eql outcome :x) "win-x")
                                        (when (eql outcome :o) "win-o"))
                    :src (mark-asset outcome)
                    :alt ""
                    :aria-hidden "true"))))))))

(defun emit-confetti (game)
  (when (player-p (game-winner game))
    (spinneret:with-html
      (:div :class "confetti"
            :aria-hidden "true"
        (loop for index below +confetti-piece-count+
              do (spinneret:with-html
                   (:span :class (format nil "confetti-piece piece-~D" index))))))))

(defun emit-player-field (mark)
  (spinneret:with-html
    (:label :class (css-classes "player-field"
                                (format nil "is-~(~A~)" (player-label mark)))
            :for (player-input-id mark)
      (:span :class "field-mark"
             :aria-hidden "true"
        (player-label mark))
      (:input :id (player-input-id mark)
              :type "text"
              :name (player-parameter-name mark)
              :maxlength +max-player-name-length+
              :value (player-input-value mark)
              :placeholder "Name"
              :aria-label (format nil "~A player name" (player-label mark))
              :autocomplete "off"))))

(defun emit-first-player-option (mark)
  (let ((selected-p (eql mark (session-first-player))))
    (spinneret:with-html
      (:label :class (css-classes "first-choice"
                                  (when selected-p "is-selected"))
        (:input :type "radio"
                :name "first-player"
                :value (string-downcase (player-label mark))
                :checked selected-p)
        (:span (player-label mark))))))

(defun emit-opponent-option (value label)
  (let ((selected-p (string= value (session-opponent-value))))
    (spinneret:with-html
      (:label :class (css-classes "opponent-choice"
                                  (when selected-p "is-selected"))
        (:input :type "radio"
                :name "opponent"
                :value value
                :checked selected-p)
        (:span label)))))

(defun emit-player-settings ()
  (spinneret:with-html
    (with-game-post-form (*games-path* :class "players-form")
      (:div :class "player-fields"
        (emit-player-field :x)
        (emit-player-field :o))
      (:fieldset :class "opponent-field"
        (:legend "Opponent")
        (:div :class "opponent-choices"
          (emit-opponent-option "human" "Human")
          (emit-opponent-option "easy" "Easy")
          (emit-opponent-option "normal" "Normal")
          (emit-opponent-option "hard" "Hard")))
      (:fieldset :class "first-player-field"
        (:legend "First")
        (:div :class "first-choices"
          (emit-first-player-option :x)
          (emit-first-player-option :o)))
      (:button :class "players-button"
               :type "submit"
               "Start"))))

(defun emit-create-room-form (&key button-tabindex)
  (spinneret:with-html
    (:form :class "room-start-form"
           :method "post"
           :action *rooms-path*
      (emit-csrf-input)
      (:button :class "reset-button"
               :type "submit"
               :tabindex button-tabindex
               "Create room"))))

(defun player-summary-active-p (game mark)
  (let ((winner (game-winner game)))
    (if winner
        (eql winner mark)
        (eql (game-next-player game) mark))))

(defun emit-player-chip (game mark)
  (spinneret:with-html
    (:span :class (css-classes "player-chip"
                               (format nil "is-~(~A~)" (player-label mark))
                               (when (player-summary-active-p game mark)
                                 "is-current"))
      (:span :class "chip-mark" (player-label mark))
      (:strong (player-name mark))
      (when (eql mark (session-computer-player))
        (spinneret:with-html
          (:span :class "chip-kind" (session-computer-label)))))))

(defun emit-player-summary (game)
  (spinneret:with-html
    (:div :class "player-strip"
      (emit-player-chip game :x)
      (emit-player-chip game :o))))

(defun emit-turn-card (game)
  (let* ((winner (game-winner game))
         (mark (cond
                 ((player-p winner) winner)
                 ((null winner) (game-next-player game)))))
    (spinneret:with-html
      (:div :class (css-classes "turn-card"
                                (when mark
                                  (format nil "is-~(~A~)"
                                          (player-label mark)))
                                (when (game-over-p game) "is-result"))
        (:span :class "status-label"
          (if (game-over-p game) "Result" "Turn"))
        (:span :class "turn-main"
          (when mark
            (spinneret:with-html
              (:img :class "turn-mark"
                    :src (mark-asset mark)
                    :alt "")))
          (:strong (result-label game)))))))

(defun status-announcement (game)
  (format nil "~A Target: ~A."
          (result-label game)
          (target-label game)))

(defun emit-status-announcement (game)
  (spinneret:with-html
    (:p :class "visually-hidden"
        :role "status"
        :aria-live "polite"
        :aria-atomic "true"
      (status-announcement game))))

(defun game-over-detail (game)
  (ecase (game-winner game)
    (:x (format nil "~A played X." (player-name :x)))
    (:o (format nil "~A played O." (player-name :o)))
    (:draw "No more winning lines are available.")))

(defun emit-game-over-dialog (game &key (action-path *games-path*)
                                       (button-label "New game")
                                       htmx-target)
  (when (game-over-p game)
    (spinneret:with-html
      (:div :class "game-over-modal"
            :role "dialog"
            :aria-modal "true"
            :aria-labelledby "game-over-title"
            :aria-describedby "game-over-detail"
        (:div :class "game-over-panel"
          (:p :class "dialog-eyebrow" "Game over")
          (:h2 :id "game-over-title"
            (result-label game))
          (:p :class "dialog-detail"
              :id "game-over-detail"
            (game-over-detail game))
          (:form :class "dialog-actions"
                 :method "post"
                 :action action-path
                 :hx-post (when htmx-target action-path)
                 :hx-target htmx-target
                 :hx-swap (when htmx-target "outerHTML")
            (emit-csrf-input)
            (:button :class "dialog-button"
                     :type "submit"
                     :autofocus t
                     button-label)))))))

(defun emit-game-fragment (game &key notice)
  (spinneret:with-html
    (:section :id "game"
              :class (css-classes "game-shell"
                                  (when (and (null (game-winner game))
                                             (null (game-active-board game)))
                                    "is-any-board")
                                  (when (plusp (game-move-count game))
                                    "is-started")
                                  (when (game-over-p game) "is-over"))
      (:header :class "game-header"
        (:div :class "topbar"
          (:div :class "brand-lockup"
            (:span :class "brand-mark"
                   :aria-hidden "true")
            (:div :class "title-block"
              (:h1 "Ultimate Tic Tac Toe")))
          (:div :class "topbar-actions"
            (with-game-post-form (*games-path* :class "reset-form")
              (:button :class "reset-button"
                       :type "submit"
                       :tabindex (when (game-over-p game) -1)
                       :aria-label "Start a new game"
                       "New game"))
            (emit-create-room-form :button-tabindex (when (game-over-p game)
                                                     -1))))
        (:div :class "status-row"
          (emit-turn-card game)
          (:div :class "target-card"
            (:span :class "status-label" "Target")
            (:strong (target-label game))))
        (emit-status-announcement game)
        (if (zerop (game-move-count game))
            (emit-player-settings)
            (emit-player-summary game)))
      (emit-confetti game)
      (when notice
        (spinneret:with-html
          (:p :class "notice"
              :role "status"
              :aria-live "polite"
              notice)))
      (:div :class "play-layout"
        (:div :class "macro-board"
          (loop for board below +board-count+
                do (emit-local-board game board))))
      (emit-game-over-dialog game
                             :action-path *games-path*
                             :button-label "New game"
                             :htmx-target "#game"))))

(defun render-game-fragment (game &key notice)
  (spinneret:with-html-string
    (emit-game-fragment game :notice notice)))

(defun room-role-label (view)
  (if (eql (room-view-role view) :player)
      (format nil "You are ~A" (player-label (room-view-mark view)))
      "Watching"))

(defun room-player-may-move-p (view)
  (let ((game (room-view-game view)))
    (and (eql (room-view-role view) :player)
         (not (game-over-p game))
         (eql (room-view-mark view)
              (game-next-player game)))))

(defun emit-room-seat-control (view mark)
  (let ((code (room-view-code view)))
    (spinneret:with-html
      (cond
        ((eql mark (room-view-mark view))
         (spinneret:with-html
           (:span :class (css-classes "room-seat"
                                      (format nil "is-~(~A~)" (player-label mark)))
                  (format nil "You are ~A" (player-label mark)))))
        ((room-view-seat-open-p view mark)
         (with-room-post-form ((room-seat-path code mark) :class "room-seat-form")
           (:button :class "room-seat-button"
                    :type "submit"
             (format nil "Claim ~A" (player-label mark)))))
        (t
         (spinneret:with-html
           (:span :class (css-classes "room-seat"
                                      (format nil "is-~(~A~)" (player-label mark)))
                  (format nil "~A seated" (player-label mark)))))))))

(defun emit-room-seat-controls (view)
  (spinneret:with-html
    (:div :class "room-seats"
      (emit-room-seat-control view :x)
      (emit-room-seat-control view :o))))

(defun room-cell-aria-label (game board cell)
  (format nil "Play ~A in the ~A board, ~A square"
          (player-label (game-next-player game))
          (grid-position-aria-label board)
          (grid-position-aria-label cell)))

(defun emit-room-cell (view board cell)
  (let* ((game (room-view-game view))
         (mark (mark-at game board cell))
         (legal-p (legal-move-p game board cell))
         (control-p (and legal-p (room-player-may-move-p view))))
    (spinneret:with-html
      (:div :class (css-classes "micro-cell"
                                (when mark "is-filled")
                                (when control-p "is-playable"))
        (cond
          (mark
           (emit-mark mark))
          (control-p
           (with-room-post-form ((room-moves-path (room-view-code view))
                                 :class "cell-form")
             (:input :type "hidden"
                     :name "board"
                     :value board)
             (:input :type "hidden"
                     :name "cell"
                     :value cell)
             (:input :type "hidden"
                     :name "revision"
                     :value (room-view-revision view))
             (:button :class "cell-button"
                      :type "submit"
                      :aria-label (room-cell-aria-label game board cell)
               (:span :class "cell-dot"
                      :aria-hidden "true"))))
          (t
           (spinneret:with-html
             (:span :class "cell-blank"
                    :aria-hidden "true"))))))))

(defun emit-room-local-board (view board)
  (let* ((game (room-view-game view))
         (outcome (board-outcome game board))
         (available-p (available-board-p game board))
         (active-board (game-active-board game))
         (active-p (and active-board (= board active-board))))
    (spinneret:with-html
      (:section :class (css-classes "local-board"
                                    (when available-p "is-available")
                                    (when (and available-p (null active-board))
                                      "is-choice")
                                    (when active-p "is-active")
                                    (when (eql outcome :x) "is-won-x")
                                    (when (eql outcome :o) "is-won-o")
                                    (when (eql outcome :draw) "is-draw")
                                    (when (global-winning-board-p game board)
                                      "is-global-win-board"))
                :aria-label (format nil "Board ~D, ~A"
                                    (1+ board)
                                    (outcome-label outcome))
        (:div :class "micro-grid"
          (loop for cell below +board-count+
                do (emit-room-cell view board cell))
          (when (player-p outcome)
            (spinneret:with-html
              (:img :class (css-classes "board-win-glyph"
                                        (when (eql outcome :x) "win-x")
                                        (when (eql outcome :o) "win-o"))
                    :src (mark-asset outcome)
                    :alt ""
                    :aria-hidden "true"))))))))

(defun emit-room-game-fragment (view &key notice)
  (let ((game (room-view-game view)))
    (spinneret:with-html
      (:section :id "room-game"
                :class (css-classes "game-shell"
                                    "room-shell"
                                    (when (and (null (game-winner game))
                                               (null (game-active-board game)))
                                      "is-any-board")
                                    (when (plusp (game-move-count game))
                                      "is-started")
                                    (when (game-over-p game) "is-over"))
        (:header :class "game-header"
          (:div :class "topbar"
            (:div :class "brand-lockup"
              (:span :class "brand-mark"
                     :aria-hidden "true")
              (:div :class "title-block"
                (:h1 (format nil "Room ~A" (room-view-code view)))
                (:p :class "room-role" (room-role-label view)))))
          (:div :class "status-row"
            (emit-turn-card game)
            (:div :class "target-card"
              (:span :class "status-label" "Target")
              (:strong (target-label game))))
          (emit-status-announcement game)
          (emit-room-seat-controls view))
        (emit-confetti game)
        (when notice
          (spinneret:with-html
            (:p :class "notice"
                :role "status"
                :aria-live "polite"
                notice)))
        (:div :class "play-layout"
          (:div :class "macro-board"
            (loop for board below +board-count+
                  do (emit-room-local-board view board))))
        (emit-game-over-dialog game
                               :action-path *rooms-path*
                               :button-label "New room")))))

(defun render-room-game-fragment (view &key notice)
  (spinneret:with-html-string
    (emit-room-game-fragment view :notice notice)))

(defun emit-footer-separator ()
  (spinneret:with-html
    (:span :class "footer-separator"
           :aria-hidden "true"
           "·")))

(defun emit-page-footer (&key game out-of-band)
  (let* ((background-hidden-p (and game (game-over-p game)))
         (background-tabindex (when background-hidden-p -1)))
    (spinneret:with-html
      (:footer :id "site-footer"
               :class "site-footer"
               :aria-hidden (when background-hidden-p "true")
               :hx-swap-oob (when out-of-band "outerHTML")
        (:a :href (source-code-url)
            :tabindex background-tabindex
            "Source code")
        (emit-footer-separator)
        (:a :href (repository-file-url "LICENSE")
            :rel "license"
            :tabindex background-tabindex
            "License")
        (emit-footer-separator)
        (:a :href *legal-notices-path*
            :tabindex background-tabindex
            "Legal notices")))))

(defun render-htmx-response (game &key notice)
  (concatenate
   'string
   (render-game-fragment game :notice notice)
   (spinneret:with-html-string
     (emit-page-footer :game game :out-of-band t))))

(defun render-room-htmx-response (view &key notice)
  (let ((game (room-view-game view)))
    (concatenate
     'string
     (render-room-game-fragment view :notice notice)
     (spinneret:with-html-string
       (emit-page-footer :game game :out-of-band t)))))

(defun render-legal-notices-page ()
  (concatenate
   'string
   "<!doctype html>"
   (spinneret:with-html-string
     (:html :lang "en"
       (:head
         (:meta :charset "utf-8")
         (:meta :name "viewport"
                :content "width=device-width, initial-scale=1")
         (:title "Legal Notices - Ultimate Tic Tac Toe")
         (:link :rel "icon"
                :href "/icon.svg"
                :type "image/svg+xml")
         (:link :rel "stylesheet"
                :href "/style.css"))
       (:body :class "legal-body"
         (:main :class "legal-page"
           (:article :class "legal-shell"
             (:p :class "legal-kicker" "Ultimate Tic Tac Toe")
             (:h1 "Legal Notices")
             (:section :class "legal-section"
               (:h2 "Copyright")
               (:p "Copyright (C) Contributors."))
             (:section :class "legal-section"
               (:h2 "License")
               (:p "This program is free software under the GNU Affero General Public License, version 3 or later. You may convey and modify it under that license."))
             (:section :class "legal-section"
               (:h2 "No Warranty")
               (:p "This program is provided without warranty, unless a separate written warranty is provided."))
             (:section :class "legal-section"
               (:h2 "Source")
               (:p "The corresponding source code is available from "
                   (:a :href (source-code-url) "the project repository")
                   ". The full license text is available in "
                   (:a :href (repository-file-url "LICENSE")
                       :rel "license"
                       "LICENSE")
                   "."))
             (:p :class "legal-actions"
                   (:a :href "/" "Back to game")))
           (emit-page-footer)))))))

(defun emit-htmx-config ()
  (spinneret:with-html
    (:meta :name "htmx-config"
           :content "{\"includeIndicatorStyles\": false, \"allowEval\": false, \"allowScriptTags\": false, \"attributesToSettle\": [\"class\", \"width\", \"height\"]}")))

(defun render-page (game &key notice)
  (concatenate
   'string
   "<!doctype html>"
   (spinneret:with-html-string
     (:html :lang "en"
       (:head
         (:meta :charset "utf-8")
         (:meta :name "viewport"
                :content "width=device-width, initial-scale=1")
         (:title "Ultimate Tic Tac Toe")
         (:link :rel "icon"
                :href "/icon.svg"
                :type "image/svg+xml")
         (:link :rel "stylesheet"
                :href "/style.css")
         (emit-htmx-config)
         (:script :src "/htmx.min.js"
                  :defer t)
         (:script :src "/app.js"
                  :defer t))
       (:body
         (:main :class "app"
           (emit-game-fragment game :notice notice)
           (emit-page-footer :game game)))))))

(defun render-room-page (view &key notice)
  (let ((game (room-view-game view)))
    (concatenate
     'string
     "<!doctype html>"
     (spinneret:with-html-string
       (:html :lang "en"
         (:head
           (:meta :charset "utf-8")
           (:meta :name "viewport"
                  :content "width=device-width, initial-scale=1")
           (:title (format nil "Room ~A - Ultimate Tic Tac Toe"
                           (room-view-code view)))
           (:link :rel "icon"
                  :href "/icon.svg"
                  :type "image/svg+xml")
           (:link :rel "stylesheet"
                  :href "/style.css")
           (emit-htmx-config)
           (:script :src "/htmx.min.js"
                    :defer t)
           (:script :src "/app.js"
                    :defer t))
         (:body
           (:main :class "app"
             (emit-room-game-fragment view :notice notice)
             (emit-page-footer :game game))))))))

(defun room-rejection-notice (rejection)
  (ecase (room-rejected-reason rejection)
    (:room-not-found "That room was not found.")
    (:invalid-seat "That seat was not understood.")
    (:missing-token "Reload the room and try again.")
    (:already-seated "This browser is already seated in the room.")
    (:seat-occupied "That seat is already taken.")
    (:watcher "Watchers cannot play moves.")
    (:stale-revision "The room changed. Review the latest board and try again.")
    (:wrong-turn "It is not your turn.")
    ((:invalid-board :invalid-cell) "That move was not understood.")
    (:game-over "The game is already over.")
    (:closed-board "That board is already complete.")
    (:wrong-board "That move belongs in the target board.")
    (:occupied-cell "That square is no longer available.")))

(defun room-view-for-request (code)
  (view-room *room-repository* code (room-session-token code)))

(defun room-post-response (code view &key notice)
  (if (htmx-request-p)
      (html-response (render-room-htmx-response view :notice notice))
      (progn
        (remember-room-notice code notice)
        (redirect-response (room-path code)))))

(defun room-page-handler (params)
  (let ((code (request-room-code params)))
    (multiple-value-bind (view foundp)
        (and code (room-view-for-request code))
      (if foundp
          (html-response
           (render-room-page view :notice (pop-room-notice code)))
          (not-found-response)))))

(defun room-game-handler (params)
  (let ((code (request-room-code params)))
    (multiple-value-bind (view foundp)
        (and code (room-view-for-request code))
      (if foundp
          (html-response (render-room-game-fragment view))
          (not-found-response)))))

(defun rooms-handler (params)
  (if (csrf-parameter-valid-p params)
      (let ((view (create-room *room-repository*)))
        (redirect-response (room-path (room-view-code view))))
      (reject-csrf-token)))

(defun room-seat-handler (params)
  (if (csrf-parameter-valid-p params)
      (let* ((code (request-room-code params))
             (mark (parse-player-mark (route-parameter params :mark))))
        (if code
            (multiple-value-bind (view acceptedp rejection)
                (claim-seat *room-repository*
                            code
                            mark
                            (ensure-room-session-token code))
              (cond
                ((null view)
                 (not-found-response))
                (acceptedp
                 (room-post-response code view))
                (t
                 (room-post-response
                  code
                  view
                  :notice (room-rejection-notice rejection)))))
            (not-found-response)))
      (reject-csrf-token)))

(defun room-move-handler (params)
  (if (csrf-parameter-valid-p params)
      (let* ((code (request-room-code params))
             (board-index (parse-index (form-parameter params "board")))
             (cell-index (parse-index (form-parameter params "cell")))
             (revision (parse-room-revision (form-parameter params "revision"))))
        (cond
          ((null code)
           (not-found-response))
          ((not (and board-index cell-index revision))
           (multiple-value-bind (view foundp)
               (room-view-for-request code)
             (if foundp
                 (room-post-response code view
                                     :notice "That move was not understood.")
                 (not-found-response))))
          (t
           (multiple-value-bind (view acceptedp rejection)
               (play-room-move *room-repository*
                               code
                               (room-session-token code)
                               revision
                               board-index
                               cell-index)
             (cond
               ((null view)
                (not-found-response))
               (acceptedp
                (room-post-response code view))
               (t
                (room-post-response code view
                                    :notice (room-rejection-notice rejection))))))))
      (reject-csrf-token)))

(defun home-handler (params)
  (declare (ignore params))
  (with-current-game-locked ()
    (multiple-value-bind (game recoveredp)
        (current-game)
      (let ((notice (pop-notice)))
        (setf game (maybe-play-computer-turn game))
        (html-response
         (render-page game
                      :notice (if recoveredp
                                  *recovered-game-notice*
                                  notice)))))))

(defun current-game-handler (params)
  (declare (ignore params))
  (with-current-game-locked ()
    (multiple-value-bind (game recoveredp)
        (current-game)
      (setf game (maybe-play-computer-turn game))
      (html-response
       (if (htmx-request-p)
           (render-htmx-response
            game
            :notice (and recoveredp *recovered-game-notice*))
           (render-page
            game
            :notice (and recoveredp *recovered-game-notice*)))))))

(defun legal-notices-handler (params)
  (declare (ignore params))
  (html-response (render-legal-notices-page)))

(defun health-handler (params)
  (declare (ignore params))
  (clack-response 200
                  (format nil "ok~%")
                  :content-type *plain-text-content-type*
                  :headers (list :cache-control "no-store")))

(defun version-handler (params)
  (declare (ignore params))
  (clack-response 200
                  (format nil "ultimate-tic-tac-toe ~A~%" (app-version))
                  :content-type *plain-text-content-type*
                  :headers (list :cache-control "no-store")))

(defun move-handler (params)
  (if (csrf-parameter-valid-p params)
      (with-current-game-locked ()
        (multiple-value-bind (game recoveredp)
            (current-game)
          (let ((board-index (parse-index (form-parameter params "board")))
                (cell-index (parse-index (form-parameter params "cell"))))
            (cond
              (recoveredp
               (respond-after-post
                (maybe-play-computer-turn game)
                :notice *recovered-game-notice*))
              ((and board-index cell-index)
               (multiple-value-bind (updated-game acceptedp rejection)
                   (play-move game board-index cell-index)
                 (declare (ignore updated-game))
                 (when acceptedp
                   (maybe-play-computer-turn game))
                 (respond-after-post
                  game
                  :notice (unless acceptedp
                            (move-rejection-notice rejection)))))
              (t
               (respond-after-post game
                                   :notice "That move was not understood."))))))
      (reject-csrf-token)))

(defun games-handler (params)
  (if (csrf-parameter-valid-p params)
      (with-current-game-locked ()
        (let ((first-mark (parse-player-mark
                           (form-parameter params "first-player"))))
          (when (form-submitted-p params "player-x" "player-o" "first-player"
                                  "opponent")
            (remember-player-settings (form-parameter params "player-x")
                                      (form-parameter params "player-o")
                                      first-mark
                                      (form-parameter params "opponent")))
          (respond-after-post
           (maybe-play-computer-turn
            (replace-current-game :first-player first-mark)))))
      (reject-csrf-token)))

(defun make-asset-handler (relative-path content-type)
  (lambda (params)
    (declare (ignore params))
    (asset-response relative-path content-type)))

(defun install-route (app method path handler)
  (setf (ningle:route app path :method method) handler)
  app)

(defun install-routes (app routes)
  (dolist (route routes app)
    (destructuring-bind (method path handler) route
      (install-route app method path handler))))

(defun install-static-asset-routes (app)
  (dolist (asset *static-assets* app)
    (destructuring-bind (path relative-path content-type) asset
      (install-route app :get path
                     (make-asset-handler relative-path content-type)))))

(defun make-routes ()
  (let ((app (make-instance 'ningle:app)))
    (install-routes
     app
     (list (list :get "/" #'home-handler)
           (list :get *legal-notices-path* #'legal-notices-handler)
           (list :get *health-path* #'health-handler)
           (list :get *version-path* #'version-handler)
           (list :get *current-game-path* #'current-game-handler)
           (list :post *rooms-path* #'rooms-handler)
           (list :get "/rooms/:code/game" #'room-game-handler)
           (list :get "/rooms/:code" #'room-page-handler)
           (list :post "/rooms/:code/seats/:mark" #'room-seat-handler)
           (list :post "/rooms/:code/moves" #'room-move-handler)
           (list :post *games-path* #'games-handler)
           (list :post *current-game-moves-path* #'move-handler)
           (list :post "/move" #'move-handler)
           (list :post "/players" #'games-handler)
           (list :post "/reset" #'games-handler)))
    (install-static-asset-routes app)
    app))

(defun make-app ()
  (wrap-default-headers
   (lack:builder
     (:session :keep-empty nil)
     #'wrap-request-env
     (make-routes))))

(defun clack-hunchentoot-symbol (name)
  (let ((package (find-package *clack-hunchentoot-package-name*)))
    (or (and package (find-symbol name package))
        (error "Could not find ~A in ~A." name *clack-hunchentoot-package-name*))))

;; Clack's exported Hunchentoot runner blocks and owns shutdown. The test
;; lifecycle keeps Hunchentoot's acceptor directly so failures are synchronous
;; and shutdown is clean; keep the private adapter names quarantined here.
(defun initialize-clack-hunchentoot ()
  (funcall (symbol-function (clack-hunchentoot-symbol "INITIALIZE"))))

(defun make-clack-hunchentoot-acceptor (port debug)
  (make-instance (clack-hunchentoot-symbol "CLACK-ACCEPTOR")
                 :app (make-app)
                 :address "127.0.0.1"
                 :port port
                 :debug debug
                 :access-log-destination nil
                 :error-template-directory nil
                 :persistent-connections-p nil))

(defun start-hunchentoot (port debug)
  (initialize-clack-hunchentoot)
  (hunchentoot:start (make-clack-hunchentoot-acceptor port debug)))

(defun start (&key (port 4242) (server :woo) (debug nil) silent)
  (stop)
  (setf *server*
        (if (eql server :hunchentoot)
            (start-hunchentoot port debug)
            (clack:clackup (make-app)
                           :server server
                           :port port
                           :debug debug
                           :silent silent
                           :use-default-middlewares nil
                           :persistent-connections-p nil))
        *server-port* port)
  *server*)

(defun stop ()
  (when *server*
    (if (typep *server* 'hunchentoot:acceptor)
        (hunchentoot:stop *server*)
        (clack:stop *server*))
    (setf *server* nil
          *server-port* nil))
  nil)

(defun server-port ()
  *server-port*)
