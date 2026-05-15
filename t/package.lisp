;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(defpackage #:ultimate-tic-tac-toe.tests
  (:use #:cl #:fiveam)
  (:import-from #:ultimate-tic-tac-toe.rules
                #:local-board-outcome-symbols
                #:global-outcome-symbols
                #:winning-line-index-symbols)
  (:import-from #:ultimate-tic-tac-toe.game
                #:+board-count+
                #:make-game
                #:game-cells
                #:game-board-outcomes
                #:game-next-player
                #:game-active-board
                #:game-winner
                #:game-move-count
                #:move-rejected
                #:move-rejected-reason
                #:board-outcome
                #:board-winning-line
                #:global-winning-line
                #:winning-line-positions
                #:legal-move-p
                #:play-move))
