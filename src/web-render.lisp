;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(in-package #:ultimate-tic-tac-toe.web)

(eval-when (:compile-toplevel :load-toplevel :execute)
  (pushnew "hx-" spinneret:*unvalidated-attribute-prefixes* :test #'string=)
  (pushnew "sse-" spinneret:*unvalidated-attribute-prefixes* :test #'string=))

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
            :hx-target "#room-stream"
            :hx-swap "outerHTML"
       (emit-csrf-input)
       ,@body)))

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

(defun emit-empty-cell ()
  (spinneret:with-html
    (:span :class "cell-blank"
           :aria-hidden "true")))

(defun emit-move-fields (board cell &key revision)
  (spinneret:with-html
    (:input :type "hidden"
            :name "board"
            :value board)
    (:input :type "hidden"
            :name "cell"
            :value cell)
    (when revision
      (spinneret:with-html
        (:input :type "hidden"
                :name "revision"
                :value revision)))))

(defun emit-cell-button (aria-label)
  (spinneret:with-html
    (:button :class "cell-button"
             :type "submit"
             :aria-label aria-label
      (:span :class "cell-dot"
             :aria-hidden "true"))))

(defun emit-cell-body (mark playable-p emit-control)
  (cond
    (mark
     (emit-mark mark))
    (playable-p
     (funcall emit-control))
    (t
     (emit-empty-cell))))

(defun emit-micro-cell (mark playable-p emit-control)
  (spinneret:with-html
    (:div :class (css-classes "micro-cell"
                              (when mark "is-filled")
                              (when playable-p "is-playable"))
      (emit-cell-body mark playable-p emit-control))))

(defun emit-game-cell-control (game board cell)
  (with-game-post-form (*current-game-moves-path* :class "cell-form")
    (emit-move-fields board cell)
    (emit-cell-button (cell-aria-label game board cell))))

(defun emit-cell (game board cell)
  (let ((mark (mark-at game board cell))
        (legal-p (legal-move-p game board cell)))
    (emit-micro-cell mark
                     legal-p
                     (lambda ()
                       (emit-game-cell-control game board cell)))))

(defun local-board-css-classes (game board)
  (let* ((outcome (board-outcome game board))
         (available-p (available-board-p game board))
         (active-board (game-active-board game))
         (active-p (and active-board (= board active-board))))
    (css-classes "local-board"
                 (when available-p "is-available")
                 (when (and available-p (null active-board)) "is-choice")
                 (when active-p "is-active")
                 (when (eql outcome :x) "is-won-x")
                 (when (eql outcome :o) "is-won-o")
                 (when (eql outcome :draw) "is-draw")
                 (when (global-winning-board-p game board)
                   "is-global-win-board"))))

(defun local-board-aria-label (game board)
  (format nil "Board ~D, ~A"
          (1+ board)
          (outcome-label (board-outcome game board))))

(defun emit-board-win-glyph (outcome)
  (when (player-p outcome)
    (spinneret:with-html
      (:img :class (css-classes "board-win-glyph"
                                (when (eql outcome :x) "win-x")
                                (when (eql outcome :o) "win-o"))
            :src (mark-asset outcome)
            :alt ""
            :aria-hidden "true"))))

(defun emit-local-board-grid (game board emit-cell)
  (spinneret:with-html
    (:section :class (local-board-css-classes game board)
              :aria-label (local-board-aria-label game board)
      (:div :class "micro-grid"
        (loop for cell below +board-count+
              do (funcall emit-cell cell))
        (emit-board-win-glyph (board-outcome game board))))))

(defun emit-local-board (game board)
  (emit-local-board-grid game
                         board
                         (lambda (cell)
                           (emit-cell game board cell))))

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

(defun game-shell-css-classes (game &rest extra-classes)
  (apply #'css-classes
         "game-shell"
         (append extra-classes
                 (list (when (and (null (game-winner game))
                                  (null (game-active-board game)))
                         "is-any-board")
                       (when (plusp (game-move-count game))
                         "is-started")
                       (when (game-over-p game) "is-over")))))

(defun emit-brand-lockup (title &key subtitle)
  (spinneret:with-html
    (:div :class "brand-lockup"
      (:span :class "brand-mark"
             :aria-hidden "true")
      (:div :class "title-block"
        (:h1 title)
        (when subtitle
          (spinneret:with-html
            (:p :class "room-role" subtitle)))))))

(defun emit-target-card (game)
  (spinneret:with-html
    (:div :class "target-card"
      (:span :class "status-label" "Target")
      (:strong (target-label game)))))

(defun emit-status-row (game)
  (spinneret:with-html
    (:div :class "status-row"
      (emit-turn-card game)
      (emit-target-card game))))

(defun emit-notice (notice)
  (when notice
    (spinneret:with-html
      (:p :class "notice"
          :role "status"
          :aria-live "polite"
          notice))))

(defun emit-play-layout (emit-board)
  (spinneret:with-html
    (:div :class "play-layout"
      (:div :class "macro-board"
        (loop for board below +board-count+
              do (funcall emit-board board))))))

(defun emit-game-fragment (game &key notice)
  (spinneret:with-html
    (:section :id "game"
              :class (game-shell-css-classes game)
      (:header :class "game-header"
        (:div :class "topbar"
          (emit-brand-lockup "Ultimate Tic Tac Toe")
          (:div :class "topbar-actions"
            (with-game-post-form (*games-path* :class "reset-form")
              (:button :class "reset-button"
                       :type "submit"
                       :tabindex (when (game-over-p game) -1)
                       :aria-label "Start a new game"
                       "New game"))
            (emit-create-room-form :button-tabindex (when (game-over-p game)
                                                     -1))))
        (emit-status-row game)
        (emit-status-announcement game)
        (if (zerop (game-move-count game))
            (emit-player-settings)
            (emit-player-summary game)))
      (emit-confetti game)
      (emit-notice notice)
      (emit-play-layout (lambda (board)
                          (emit-local-board game board)))
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

(defun emit-room-cell-control (view game board cell)
  (with-room-post-form ((room-moves-path (room-view-code view))
                        :class "cell-form")
    (emit-move-fields board cell :revision (room-view-revision view))
    (emit-cell-button (room-cell-aria-label game board cell))))

(defun emit-room-cell (view board cell)
  (let* ((game (room-view-game view))
         (mark (mark-at game board cell))
         (legal-p (legal-move-p game board cell))
         (control-p (and legal-p (room-player-may-move-p view))))
    (emit-micro-cell mark
                     control-p
                     (lambda ()
                       (emit-room-cell-control view game board cell)))))

(defun emit-room-local-board (view board)
  (let ((game (room-view-game view)))
    (emit-local-board-grid game
                           board
                           (lambda (cell)
                             (emit-room-cell view board cell)))))

(defun emit-room-game-fragment (view &key notice)
  (let ((game (room-view-game view)))
    (spinneret:with-html
      (:section :id "room-game"
                :class (game-shell-css-classes game "room-shell")
        (:header :class "game-header"
          (:div :class "topbar"
            (emit-brand-lockup (format nil "Room ~A" (room-view-code view))
                               :subtitle (room-role-label view)))
          (emit-status-row game)
          (emit-status-announcement game)
          (emit-room-seat-controls view))
        (emit-confetti game)
        (emit-notice notice)
        (emit-play-layout (lambda (board)
                            (emit-room-local-board view board)))
        (emit-game-over-dialog game
                               :action-path *rooms-path*
                               :button-label "New room")))))

(defun render-room-game-fragment (view &key notice)
  (spinneret:with-html-string
    (emit-room-game-fragment view :notice notice)))

(defun emit-room-stream (view &key notice)
  (spinneret:with-html
    (:div :id "room-stream"
          :hx-ext "sse"
          :sse-connect (room-events-path (room-view-code view))
          :sse-swap *room-update-event-name*
          :hx-target "#room-game"
          :hx-swap "outerHTML"
      (emit-room-game-fragment view :notice notice))))

(defun render-room-stream (view &key notice)
  (spinneret:with-html-string
    (emit-room-stream view :notice notice)))

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
     (render-room-stream view :notice notice)
     (spinneret:with-html-string
       (emit-page-footer :game game :out-of-band t)))))

(defun emit-htmx-config ()
  (spinneret:with-html
    (:meta :name "htmx-config"
           :content "{\"includeIndicatorStyles\": false, \"allowEval\": false, \"allowScriptTags\": false, \"attributesToSettle\": [\"class\", \"width\", \"height\"]}")))

(defun emit-deferred-script (path)
  (spinneret:with-html
    (:script :src path
             :defer t)))

(defun emit-document-head (title &key htmx-config-p scripts)
  (spinneret:with-html
    (:head
      (:meta :charset "utf-8")
      (:meta :name "viewport"
             :content "width=device-width, initial-scale=1")
      (:title title)
      (:link :rel "icon"
             :href "/icon.svg"
             :type "image/svg+xml")
      (:link :rel "stylesheet"
             :href "/style.css")
      (when htmx-config-p
        (emit-htmx-config))
      (dolist (script scripts)
        (emit-deferred-script script)))))

(defun render-legal-notices-page ()
  (concatenate
   'string
   "<!doctype html>"
   (spinneret:with-html-string
     (:html :lang "en"
       (emit-document-head "Legal Notices - Ultimate Tic Tac Toe")
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
       (emit-document-head "Ultimate Tic Tac Toe"
                           :htmx-config-p t
                           :scripts '("/htmx.min.js" "/app.js"))
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
         (emit-document-head (format nil "Room ~A - Ultimate Tic Tac Toe"
                                     (room-view-code view))
                             :htmx-config-p t
                             :scripts '("/htmx.min.js"
                                        "/htmx-ext-sse.js"
                                        "/app.js"))
         (:body
           (:main :class "app"
             (emit-room-stream view :notice notice)
             (emit-page-footer :game game))))))))
