;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(defpackage #:ultimate-tic-tac-toe.rules
  (:use #:coalton #:coalton-prelude)
  (:local-nicknames (#:sym #:coalton-library/symbol))
  (:export
   #:local-board-outcome-symbols
   #:global-outcome-symbols
   #:winning-line-index-symbols))

(defpackage #:ultimate-tic-tac-toe.game
  (:use #:cl)
  (:import-from #:ultimate-tic-tac-toe.rules
                #:local-board-outcome-symbols
                #:global-outcome-symbols
                #:winning-line-index-symbols)
  (:export
   #:+board-count+
   #:game
   #:make-game
   #:player-p
   #:player-label
   #:outcome-label
   #:valid-index-p
   #:game-board-outcomes
   #:game-active-board
   #:game-cells
   #:game-next-player
   #:game-winner
   #:game-move-count
   #:move-rejected
   #:move-rejected-game
   #:move-rejected-board
   #:move-rejected-cell
   #:move-rejected-reason
   #:move-rejection-reason
   #:board-outcome
   #:board-winning-line
   #:global-winning-line
   #:winning-line-positions
   #:mark-at
   #:legal-move-p
   #:available-board-p
   #:play-move
   #:game-over-p))

(defpackage #:ultimate-tic-tac-toe.web
  (:use #:cl)
  (:import-from #:ultimate-tic-tac-toe.game
                #:+board-count+
                #:make-game
                #:player-p
                #:player-label
                #:outcome-label
                #:game-next-player
                #:game-move-count
                #:game-active-board
                #:game-winner
                #:move-rejected-reason
                #:board-outcome
                #:global-winning-line
                #:winning-line-positions
                #:mark-at
                #:legal-move-p
                #:available-board-p
                #:play-move
                #:game-over-p)
  (:export
   #:start
   #:stop
   #:server-port))
