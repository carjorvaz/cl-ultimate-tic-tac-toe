;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(in-package #:ultimate-tic-tac-toe.game)

(defconstant +board-count+ 9
  "The number of local boards, and of cells in each local board.")

(defparameter *winning-lines*
  '((0 1 2)
    (3 4 5)
    (6 7 8)
    (0 3 6)
    (1 4 7)
    (2 5 8)
    (0 4 8)
    (2 4 6))
  "The winning triples in row-major board coordinates.")

(defstruct (game (:constructor make-game))
  (cells (make-array (list +board-count+ +board-count+) :initial-element nil))
  (board-outcomes (make-array +board-count+ :initial-element nil))
  (next-player :x)
  (active-board nil)
  (winner nil)
  (move-count 0))

(define-condition move-rejected (condition)
  ((game :initarg :game
         :reader move-rejected-game)
   (board :initarg :board
          :reader move-rejected-board)
   (cell :initarg :cell
         :reader move-rejected-cell)
   (reason :initarg :reason
           :reader move-rejected-reason))
  (:report
   (lambda (condition stream)
     (format stream "Move ~S/~S rejected: ~S."
             (move-rejected-board condition)
             (move-rejected-cell condition)
             (move-rejected-reason condition)))))

(defun player-p (object)
  "Return true when OBJECT names one of the two players."
  (member object '(:x :o) :test #'eq))

(defun player-label (player)
  (ecase player
    (:x "X")
    (:o "O")))

(defun outcome-label (outcome)
  (ecase outcome
    (:x "X")
    (:o "O")
    (:draw "Draw")
    ((nil) "Open")))

(defun other-player (player)
  (ecase player
    (:x :o)
    (:o :x)))

(defun valid-index-p (object)
  "Return true when OBJECT is a board or cell index."
  (and (integerp object)
       (<= 0 object (1- +board-count+))))

(defun mark-at (game board cell)
  "Return the mark at BOARD/CELL, or NIL when the position is invalid or empty."
  (when (and (valid-index-p board)
             (valid-index-p cell))
    (aref (game-cells game) board cell)))

(defun board-outcome (game board)
  "Return BOARD's outcome, one of :X, :O, :DRAW, or NIL for an open board."
  (when (valid-index-p board)
    (aref (game-board-outcomes game) board)))

(defun board-complete-p (game board)
  (not (null (board-outcome game board))))

(defun nine-values (getter)
  (loop for index below +board-count+
        collect (funcall getter index)))

(defun local-board-marks (game board)
  (nine-values (lambda (cell)
                 (aref (game-cells game) board cell))))

(defun board-outcome-values (game)
  (nine-values (lambda (board)
                 (board-outcome game board))))

(defun winning-line-index (marks)
  (let ((line-index (winning-line-index-symbols marks)))
    (unless (minusp line-index)
      line-index)))

(defun winning-line-positions (line-index)
  "Return a fresh list of the positions in LINE-INDEX, or NIL if it is invalid."
  (when (and (integerp line-index)
             (<= 0 line-index)
             (< line-index (length *winning-lines*)))
    (copy-list (nth line-index *winning-lines*))))

(defun local-board-outcome (game board)
  (local-board-outcome-symbols (local-board-marks game board)))

(defun board-winning-line (game board)
  (when (and (valid-index-p board)
             (player-p (board-outcome game board)))
    (winning-line-index (local-board-marks game board))))

(defun global-outcome (game)
  (global-outcome-symbols (board-outcome-values game)))

(defun global-winning-line (game)
  (when (player-p (game-winner game))
    (winning-line-index (board-outcome-values game))))

(defun move-rejection-reason (game board cell)
  "Return a keyword reason when BOARD/CELL is not playable in GAME."
  (cond
    ((not (valid-index-p board)) :invalid-board)
    ((not (valid-index-p cell)) :invalid-cell)
    ((game-winner game) :game-over)
    ((board-complete-p game board) :closed-board)
    ((and (game-active-board game)
          (/= board (game-active-board game)))
     :wrong-board)
    ((mark-at game board cell) :occupied-cell)))

(defun make-move-rejection (game board cell)
  (let ((reason (move-rejection-reason game board cell)))
    (when reason
      (make-condition 'move-rejected
                      :game game
                      :board board
                      :cell cell
                      :reason reason))))

(defun available-board-p (game board)
  "Return true when BOARD can accept a move in GAME."
  (and (valid-index-p board)
       (null (game-winner game))
       (not (board-complete-p game board))
       (or (null (game-active-board game))
           (= board (game-active-board game)))))

(defun legal-move-p (game board cell)
  "Return true when the current player may play BOARD/CELL in GAME."
  (null (move-rejection-reason game board cell)))

(defun update-outcomes-after-move (game board)
  (setf (aref (game-board-outcomes game) board)
        (local-board-outcome game board))
  (setf (game-winner game)
        (global-outcome game)))

(defun play-move (game board cell)
  "Apply BOARD/CELL for the current player.

Returns three values: GAME, a generalized boolean indicating whether the move
was accepted, and a MOVE-REJECTED condition when it was not. GAME is mutated in
place so it can live directly in a web session."
  (let ((rejection (make-move-rejection game board cell)))
    (when rejection
      (signal rejection)
      (return-from play-move (values game nil rejection))))
  (let ((player (game-next-player game)))
    (setf (aref (game-cells game) board cell) player)
    (incf (game-move-count game))
    (update-outcomes-after-move game board)
    (unless (game-winner game)
      (setf (game-active-board game) (unless (board-complete-p game cell)
                                       cell)
            (game-next-player game) (other-player player))))
  (values game t))

(defun game-over-p (game)
  "Return true when GAME has a winner or ended in a draw."
  (not (null (game-winner game))))
