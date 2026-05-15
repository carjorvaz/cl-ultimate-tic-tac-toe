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

(test new-game-starts-open
  (let ((game (make-game)))
    (is (eql :x (game-next-player game)))
    (is (null (game-active-board game)))
    (is (legal-move-p game 0 0))
    (is (legal-move-p game 8 8))))

(test accepted-move-selects-target-board
  (let ((game (make-game)))
    (accept-move game 0 4)
    (is (eql :o (game-next-player game)))
    (is (= 4 (game-active-board game)))
    (is (not (legal-move-p game 0 1)))
    (is (legal-move-p game 4 1))))

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
