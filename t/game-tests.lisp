;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(in-package #:ultimate-tic-tac-toe.tests)

(def-suite :ultimate-tic-tac-toe)
(in-suite :ultimate-tic-tac-toe)

(defun accept-move (game board cell)
  (multiple-value-bind (updated-game acceptedp rejection)
      (play-move game board cell)
    (is (eq updated-game game))
    (is (not (null acceptedp)))
    (is (null rejection))
    game))

(defun reject-move (reason game board cell)
  (let (signaled-rejection)
    (multiple-value-bind (updated-game acceptedp rejection)
        (handler-bind ((move-rejected (lambda (condition)
                                        (setf signaled-rejection condition))))
          (play-move game board cell))
      (is (eq updated-game game))
      (is (null acceptedp))
      (is (typep rejection 'move-rejected))
      (is (eq rejection signaled-rejection))
      (is (eql reason (move-rejected-reason rejection)))
      rejection)))

(defun accept-moves (game &rest moves)
  (dolist (move moves game)
    (destructuring-bind (board cell) move
      (accept-move game board cell))))

(defun prepare-drawn-board-before-last-move (game board)
  (let ((marks #(:x :o :x
                 :x :o :o
                 :o :x :x)))
    (loop for mark across marks
          for cell below +board-count+
          unless (= cell (1- +board-count+))
            do (setf (aref (game-cells game) board cell) mark)))
  (setf (game-active-board game) nil
        (game-next-player game) :x)
  game)

(defun prepare-global-win-before-last-move (game)
  (dolist (board '(0 1))
    (dolist (cell '(0 1 2))
      (setf (aref (game-cells game) board cell) :x))
    (setf (aref (game-board-outcomes game) board) :x))
  (setf (aref (game-cells game) 2 0) :x
        (aref (game-cells game) 2 1) :x
        (game-active-board game) nil
        (game-next-player game) :x
        (game-move-count game) 8)
  game)

(defun assert-valid-game (game)
  (multiple-value-bind (validp violations)
      (valid-game-state-p game)
    (is (not (null validp)))
    (is (null violations)))
  game)

(defun invariant-reason-present-p (reason violations)
  (not (null (assoc reason violations))))

(defun game-snapshot (game)
  (list (game-next-player game)
        (game-active-board game)
        (game-winner game)
        (game-move-count game)
        (loop for board below +board-count+
              collect (board-outcome game board))
        (loop for board below +board-count+
              append (loop for cell below +board-count+
                           collect (mark-at game board cell)))))

(test new-game-starts-open
  (let ((game (make-game)))
    (is (eql :x (game-next-player game)))
    (is (null (game-active-board game)))
    (is (legal-move-p game 0 0))
    (is (legal-move-p game 8 8))
    (assert-valid-game game)))

(test game-invariant-violations-report-corruption
  (multiple-value-bind (validp violations)
      (valid-game-state-p :not-a-game)
    (is (null validp))
    (is (invariant-reason-present-p :not-a-game violations)))
  (let ((game (make-game)))
    (setf (game-active-board game) +board-count+)
    (multiple-value-bind (validp violations)
        (valid-game-state-p game)
      (is (null validp))
      (is (invariant-reason-present-p :invalid-active-board violations))))
  (let ((game (make-game)))
    (setf (aref (game-cells game) 0 0) :maybe)
    (multiple-value-bind (validp violations)
        (valid-game-state-p game)
      (is (null validp))
      (is (invariant-reason-present-p :invalid-mark violations))))
  (let ((game (make-game)))
    (setf (aref (game-cells game) 0 0) :x)
    (multiple-value-bind (validp violations)
        (valid-game-state-p game)
      (is (null validp))
      (is (invariant-reason-present-p :stale-move-count violations))))
  (let ((game (make-game)))
    (setf (aref (game-board-outcomes game) 0) :x)
    (multiple-value-bind (validp violations)
        (valid-game-state-p game)
      (is (null validp))
      (is (invariant-reason-present-p :stale-board-outcome violations))))
  (let ((game (make-game)))
    (setf (game-winner game) :x
          (game-active-board game) 0)
    (multiple-value-bind (validp violations)
        (valid-game-state-p game)
      (is (null validp))
      (is (invariant-reason-present-p :active-board-after-game-over
                                      violations)))))

(test accepted-move-selects-target-board
  (let ((game (make-game)))
    (accept-move game 0 4)
    (is (eql :o (game-next-player game)))
    (is (= 4 (game-active-board game)))
    (is (not (legal-move-p game 0 1)))
    (is (legal-move-p game 4 1))))

(test first-legal-move-follows-target-board
  (let ((game (make-game)))
    (multiple-value-bind (board cell)
        (first-legal-move game)
      (is (= 0 board))
      (is (= 0 cell)))
    (accept-move game 0 4)
    (multiple-value-bind (board cell)
        (first-legal-move game)
      (is (= 4 board))
      (is (= 0 cell)))))

(test play-first-legal-move-applies-deterministic-move
  (let ((game (make-game)))
    (multiple-value-bind (updated-game acceptedp rejection)
        (play-first-legal-move game)
      (is (eq updated-game game))
      (is (not (null acceptedp)))
      (is (null rejection))
      (is (eql :x (mark-at game 0 0)))
      (is (eql :o (game-next-player game)))
      (is (= 0 (game-active-board game)))
      (is (= 1 (game-move-count game))))))

(test reachable-game-satisfies-invariants-after-each-move
  (let ((game (make-game)))
    (assert-valid-game game)
    (dolist (move '((0 0) (0 1) (1 2) (2 0) (0 3)
                    (3 4) (4 5) (5 0) (0 6)))
      (destructuring-bind (board cell) move
        (accept-move game board cell)
        (assert-valid-game game)))))

(test deterministic-playout-satisfies-invariants
  (let ((game (make-game)))
    (loop repeat (* +board-count+ +board-count+)
          until (game-over-p game)
          do (multiple-value-bind (updated-game acceptedp rejection)
                 (play-first-legal-move game)
               (is (eq updated-game game))
               (is (not (null acceptedp)))
               (is (null rejection))
               (assert-valid-game game)))
    (is (game-over-p game))
    (assert-valid-game game)))

(test move-selectors-do-not-mutate-reachable-game
  (let ((game (make-game)))
    (accept-moves game '(0 0) '(0 1) '(1 2) '(2 0))
    (assert-valid-game game)
    (let ((snapshot (game-snapshot game)))
      (best-tactical-move game)
      (is (equal snapshot (game-snapshot game)))
      (best-strategic-move game :depth 1)
      (is (equal snapshot (game-snapshot game))))
    (assert-valid-game game)))

(test invalid-game-state-reports-invariant-violations
  (let ((game (make-game)))
    (setf (aref (game-cells game) 0 0) :not-a-player)
    (multiple-value-bind (validp violations)
        (valid-game-state-p game)
      (is (null validp))
      (is (invariant-reason-present-p :invalid-mark violations))
      (is (invariant-reason-present-p :stale-move-count violations)))))

(test stale-board-outcome-reports-invariant-violation
  (let ((game (make-game)))
    (setf (aref (game-board-outcomes game) 0) :x)
    (multiple-value-bind (validp violations)
        (valid-game-state-p game)
      (is (null validp))
      (is (invariant-reason-present-p :stale-board-outcome violations)))))

(test best-tactical-move-prefers-center
  (let ((game (make-game)))
    (multiple-value-bind (board cell)
        (best-tactical-move game)
      (is (= 0 board))
      (is (= 4 cell)))))

(test best-tactical-move-wins-local-board
  (let ((game (make-game :next-player :o :active-board 2)))
    (setf (aref (game-cells game) 2 0) :o
          (aref (game-cells game) 2 1) :o)
    (multiple-value-bind (board cell)
        (best-tactical-move game)
      (is (= 2 board))
      (is (= 2 cell)))))

(test best-tactical-move-blocks-local-board-win
  (let ((game (make-game :next-player :o :active-board 3)))
    (setf (aref (game-cells game) 3 0) :x
          (aref (game-cells game) 3 1) :x)
    (multiple-value-bind (board cell)
        (best-tactical-move game)
      (is (= 3 board))
      (is (= 2 cell)))))

(test best-tactical-move-prefers-sending-opponent-to-closed-board
  (let ((game (make-game :next-player :o :active-board 0)))
    (setf (aref (game-board-outcomes game) 1) :x)
    (multiple-value-bind (board cell)
        (best-tactical-move game)
      (is (= 0 board))
      (is (= 1 cell)))))

(test play-best-tactical-move-applies-selected-move
  (let ((game (make-game :next-player :o :active-board 2)))
    (setf (aref (game-cells game) 2 0) :o
          (aref (game-cells game) 2 1) :o)
    (multiple-value-bind (updated-game acceptedp rejection)
        (play-best-tactical-move game)
      (is (eq updated-game game))
      (is (not (null acceptedp)))
      (is (null rejection))
      (is (eql :o (mark-at game 2 2)))
      (is (eql :o (board-outcome game 2)))
      (is (eql :x (game-next-player game)))
      (is (null (game-active-board game))))))

(test best-strategic-move-wins-global-game
  (let ((game (make-game :next-player :o :active-board 2)))
    (setf (aref (game-board-outcomes game) 0) :o
          (aref (game-board-outcomes game) 1) :o
          (aref (game-cells game) 2 0) :o
          (aref (game-cells game) 2 1) :o)
    (multiple-value-bind (board cell)
        (best-strategic-move game)
      (is (= 2 board))
      (is (= 2 cell)))))

(test best-strategic-move-avoids-sending-opponent-to-global-win
  (let ((game (make-game :next-player :o :active-board 0)))
    (setf (aref (game-board-outcomes game) 3) :x
          (aref (game-board-outcomes game) 5) :x
          (aref (game-cells game) 0 0) :o
          (aref (game-cells game) 0 8) :o
          (aref (game-cells game) 4 0) :x
          (aref (game-cells game) 4 1) :x)
    (multiple-value-bind (board cell)
        (best-strategic-move game)
      (is (= 0 board))
      (is (not (= 4 cell))))))

(test best-strategic-move-does-not-mutate-game
  (let ((game (make-game :next-player :o :active-board 2)))
    (setf (aref (game-board-outcomes game) 0) :o
          (aref (game-board-outcomes game) 1) :o
          (aref (game-cells game) 2 0) :o
          (aref (game-cells game) 2 1) :o)
    (best-strategic-move game)
    (is (= 0 (game-move-count game)))
    (is (eql :o (game-next-player game)))
    (is (= 2 (game-active-board game)))
    (is (null (game-winner game)))
    (is (null (mark-at game 2 2)))
    (is (null (board-outcome game 2)))))

(test hard-search-depth-adapts-to-branching-factor
  (let ((game (make-game)))
    (is (= 81 (ultimate-tic-tac-toe.game::legal-move-count game)))
    (is (= 2 (ultimate-tic-tac-toe.game::hard-search-depth-for-position game)))
    (accept-move game 0 4)
    (is (= 9 (ultimate-tic-tac-toe.game::legal-move-count game)))
    (is (= 3 (ultimate-tic-tac-toe.game::hard-search-depth-for-position game)))))

(test hard-search-cache-matches-uncached-score
  (let ((game (make-game :next-player :o :active-board 0))
        (cache (make-hash-table :test #'equal)))
    (setf (aref (game-cells game) 0 0) :o
          (aref (game-cells game) 0 8) :o
          (aref (game-cells game) 4 0) :x
          (aref (game-cells game) 4 1) :x)
    (let ((uncached-score
            (ultimate-tic-tac-toe.game::hard-search-score game :o 2 0))
          (cached-score
            (ultimate-tic-tac-toe.game::hard-search-score game :o 2 0 cache)))
      (is (= uncached-score cached-score))
      (is (plusp (hash-table-count cache))))))

(test play-best-strategic-move-applies-selected-move
  (let ((game (make-game :next-player :o :active-board 2)))
    (setf (aref (game-board-outcomes game) 0) :o
          (aref (game-board-outcomes game) 1) :o
          (aref (game-cells game) 2 0) :o
          (aref (game-cells game) 2 1) :o)
    (multiple-value-bind (updated-game acceptedp rejection)
        (play-best-strategic-move game)
      (is (eq updated-game game))
      (is (not (null acceptedp)))
      (is (null rejection))
      (is (eql :o (mark-at game 2 2)))
      (is (eql :o (game-winner game)))
      (is (null (game-active-board game))))))

(test completed-target-board-opens-the-choice
  (let ((game (make-game)))
    (setf (aref (game-board-outcomes game) 4) :draw)
    (accept-move game 0 4)
    (is (null (game-active-board game)))))

(test completed-target-board-opens-the-choice-from-reachable-play
  (let ((game (make-game)))
    (accept-moves game
                  '(0 0) '(0 1) '(1 2) '(2 0) '(0 3)
                  '(3 4) '(4 5) '(5 0) '(0 6))
    (is (eql :x (board-outcome game 0)))
    (is (= 3 (board-winning-line game 0)))
    (is (= 6 (game-active-board game)))
    (accept-move game 6 0)
    (is (null (game-active-board game)))
    (is (eql :x (game-next-player game)))
    (is (legal-move-p game 1 1))
    (is (not (legal-move-p game 0 2)))))

(test invalid-indexes-are-rejected
  (let ((game (make-game)))
    (reject-move :invalid-board game -1 0)
    (reject-move :invalid-board game +board-count+ 0)
    (reject-move :invalid-cell game 0 -1)
    (reject-move :invalid-cell game 0 +board-count+)
    (is (= 0 (game-move-count game)))))

(test occupied-cell-is-rejected-without-changing-turn
  (let ((game (make-game)))
    (accept-move game 0 0)
    (reject-move :occupied-cell game 0 0)
    (is (eql :o (game-next-player game)))
    (is (= 1 (game-move-count game)))))

(test wrong-target-board-is-rejected
  (let ((game (make-game)))
    (accept-move game 0 4)
    (reject-move :wrong-board game 0 1)
    (is (= 4 (game-active-board game)))
    (is (= 1 (game-move-count game)))))

(test completed-board-is-rejected
  (let ((game (make-game)))
    (setf (aref (game-board-outcomes game) 4) :draw)
    (reject-move :closed-board game 4 0)
    (is (= 0 (game-move-count game)))))

(test game-over-rejects-moves
  (let ((game (make-game)))
    (setf (game-winner game) :x)
    (reject-move :game-over game 0 0)
    (is (= 0 (game-move-count game)))))

(test local-board-win-is-recorded
  (let ((game (make-game)))
    (setf (aref (game-cells game) 2 0) :x
          (aref (game-cells game) 2 1) :x
          (game-active-board game) nil
          (game-next-player game) :x)
    (accept-move game 2 2)
    (is (eql :x (board-outcome game 2)))
    (is (= 0 (board-winning-line game 2)))
    (is (not (legal-move-p game 2 3)))))

(test local-board-draw-is-recorded
  (let ((game (make-game)))
    (prepare-drawn-board-before-last-move game 3)
    (accept-move game 3 8)
    (is (eql :draw (board-outcome game 3)))
    (is (null (board-winning-line game 3)))))

(test global-win-is-recorded
  (let ((game (make-game)))
    (setf (aref (game-board-outcomes game) 0) :x
          (aref (game-board-outcomes game) 1) :x
          (aref (game-cells game) 2 0) :x
          (aref (game-cells game) 2 1) :x
          (game-active-board game) nil
          (game-next-player game) :x)
    (accept-move game 2 2)
    (is (eql :x (game-winner game)))))

(test global-win-clears-active-board-and-remains-valid
  (let ((game (prepare-global-win-before-last-move (make-game))))
    (assert-valid-game game)
    (accept-move game 2 2)
    (is (eql :x (game-winner game)))
    (is (null (game-active-board game)))
    (assert-valid-game game)))

(test global-draw-is-recorded
  (let ((game (make-game)))
    (setf (aref (game-board-outcomes game) 0) :x
          (aref (game-board-outcomes game) 1) :o
          (aref (game-board-outcomes game) 2) :x
          (aref (game-board-outcomes game) 3) :x
          (aref (game-board-outcomes game) 4) :o
          (aref (game-board-outcomes game) 5) :o
          (aref (game-board-outcomes game) 6) :o
          (aref (game-board-outcomes game) 7) :x)
    (prepare-drawn-board-before-last-move game 8)
    (accept-move game 8 8)
    (is (eql :draw (game-winner game)))))

(test global-winning-line-is-recorded
  (let ((game (make-game)))
    (setf (aref (game-board-outcomes game) 0) :o
          (aref (game-board-outcomes game) 4) :o
          (aref (game-board-outcomes game) 8) :o
          (game-winner game) :o)
    (is (= 6 (global-winning-line game)))))
