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
   #:valid-game-state-p
   #:first-legal-move
   #:best-tactical-move
   #:best-strategic-move
   #:available-board-p
   #:play-move
   #:play-first-legal-move
   #:play-best-tactical-move
   #:play-best-strategic-move
   #:game-over-p))

(defpackage #:ultimate-tic-tac-toe.rooms
  (:use #:cl)
  (:import-from #:ultimate-tic-tac-toe.game
                #:+board-count+
                #:make-game
                #:player-p
                #:game-cells
                #:game-board-outcomes
                #:game-next-player
                #:game-active-board
                #:game-winner
                #:game-move-count
                #:mark-at
                #:play-move
                #:move-rejected-reason)
  (:export
   #:make-memory-room-repository
   #:create-room
   #:room-view
   #:room-view-code
   #:room-view-game
   #:room-view-revision
   #:room-view-role
   #:room-view-mark
   #:room-view-seat-open-p
   #:view-room
   #:claim-seat
   #:play-room-move
   #:room-rejected
   #:room-rejected-reason))

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
                #:valid-game-state-p
                #:available-board-p
                #:play-move
                #:play-first-legal-move
                #:play-best-tactical-move
                #:play-best-strategic-move
                #:game-over-p)
  (:import-from #:ultimate-tic-tac-toe.rooms
                #:make-memory-room-repository
                #:create-room
                #:view-room
                #:room-view-code
                #:room-view-game
                #:room-view-revision
                #:room-view-role
                #:room-view-mark
                #:room-view-seat-open-p
                #:claim-seat
                #:play-room-move
                #:room-rejected-reason)
  (:export
   #:start
   #:stop
   #:server-port))
