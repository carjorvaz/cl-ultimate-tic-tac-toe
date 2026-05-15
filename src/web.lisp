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

(defparameter *legal-notices-path* "/legal")

(defparameter *html-content-type* "text/html; charset=utf-8")

(defparameter *default-source-code-url*
  "https://github.com/carjorvaz/cl-ultimate-tic-tac-toe")

(defparameter *system-root*
  (asdf:system-source-directory :ultimate-tic-tac-toe))

(defparameter *clack-hunchentoot-package-name*
  "CLACK.HANDLER.HUNCHENTOOT")

(defparameter *session-state-lock*
  (bordeaux-threads:make-lock "ultimate-tic-tac-toe-session-state"))

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

(defun clack-response (status body &key content-type headers)
  (list status
        (append (when content-type
                  (list :content-type content-type))
                headers)
        (list body)))

(defun html-response (body)
  (clack-response 200 body :content-type *html-content-type*))

(defun redirect-response (location)
  (clack-response 303 "" :headers (list :location location)))

(defun not-found-response ()
  (clack-response 404
                  "Not found"
                  :content-type "text/plain; charset=utf-8"))

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

(defun current-game ()
  (let ((session (request-session)))
    (or (gethash :game session)
        (setf (gethash :game session)
              (make-game :next-player (session-first-player))))))

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
        (make-game :next-player (or first-player
                                    (session-first-player)))))

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
    ((or (string-equal value "normal")
         (string-equal value "computer"))
     :normal)
    (t :human)))

(defun session-first-player ()
  (or (current-session-value :first-player)
      :x))

(defun session-opponent-mode ()
  (or (current-session-value :opponent-mode)
      (when (current-session-value :computer-player)
        :normal)
      :human))

(defun session-opponent-value ()
  (ecase (session-opponent-mode)
    (:human "human")
    (:easy "easy")
    (:normal "normal")))

(defun session-computer-player ()
  (unless (eql :human (session-opponent-mode))
    :o))

(defun session-computer-label ()
  (ecase (session-opponent-mode)
    (:easy "Easy CPU")
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
      (:normal (play-best-tactical-move game))))
  game)

(defun mark-asset (mark)
  (ecase mark
    (:x "/x.svg")
    (:o "/o.svg")))

(defun board-position-label (board)
  (aref *board-position-labels* board))

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
  (format nil "Play ~A in board ~D cell ~D"
          (player-name (game-next-player game))
          (1+ board)
          (1+ cell)))

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
          (emit-opponent-option "normal" "Normal")))
      (:fieldset :class "first-player-field"
        (:legend "First")
        (:div :class "first-choices"
          (emit-first-player-option :x)
          (emit-first-player-option :o)))
      (:button :class "players-button"
               :type "submit"
               "Start"))))

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
          (:strong :aria-live "polite"
            (result-label game)))))))

(defun game-over-detail (game)
  (ecase (game-winner game)
    (:x (format nil "~A played X." (player-name :x)))
    (:o (format nil "~A played O." (player-name :o)))
    (:draw "No more winning lines are available.")))

(defun emit-game-over-dialog (game)
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
          (with-game-post-form (*games-path* :class "dialog-actions")
            (:button :class "dialog-button"
                     :type "submit"
                     :autofocus t
                     "New game")))))))

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
          (with-game-post-form (*games-path* :class "reset-form")
            (:button :class "reset-button"
                     :type "submit"
                     :tabindex (when (game-over-p game) -1)
                     :aria-label "Start a new game"
                     "New game")))
        (:div :class "status-row"
          (emit-turn-card game)
          (:div :class "target-card"
            (:span :class "status-label" "Target")
            (:strong (target-label game))))
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
      (emit-game-over-dialog game))))

(defun render-game-fragment (game &key notice)
  (spinneret:with-html-string
    (emit-game-fragment game :notice notice)))

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
         (:script :src "/htmx.min.js"
                  :defer t)
         (:script :src "/app.js"
                  :defer t))
       (:body
         (:main :class "app"
           (emit-game-fragment game :notice notice)
           (emit-page-footer :game game)))))))

(defun home-handler (params)
  (declare (ignore params))
  (with-current-game-locked ()
    (let ((game (maybe-play-computer-turn (current-game))))
      (html-response (render-page game :notice (pop-notice))))))

(defun current-game-handler (params)
  (declare (ignore params))
  (with-current-game-locked ()
    (let ((game (maybe-play-computer-turn (current-game))))
      (html-response
       (if (htmx-request-p)
           (render-htmx-response game)
           (render-page game))))))

(defun legal-notices-handler (params)
  (declare (ignore params))
  (html-response (render-legal-notices-page)))

(defun move-handler (params)
  (if (csrf-parameter-valid-p params)
      (with-current-game-locked ()
        (let ((game (current-game))
              (board-index (parse-index (form-parameter params "board")))
              (cell-index (parse-index (form-parameter params "cell"))))
          (if (and board-index cell-index)
              (multiple-value-bind (updated-game acceptedp rejection)
                  (play-move game board-index cell-index)
                (declare (ignore updated-game))
                (when acceptedp
                  (maybe-play-computer-turn game))
                (respond-after-post
                 game
                 :notice (unless acceptedp
                           (move-rejection-notice rejection))))
              (respond-after-post game
                                  :notice "That move was not understood."))))
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
           (list :get *current-game-path* #'current-game-handler)
           (list :post *games-path* #'games-handler)
           (list :post *current-game-moves-path* #'move-handler)
           (list :post "/move" #'move-handler)
           (list :post "/players" #'games-handler)
           (list :post "/reset" #'games-handler)))
    (install-static-asset-routes app)
    app))

(defun make-app ()
  (lack:builder
    (:session :keep-empty nil)
    #'wrap-request-env
    (make-routes)))

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
