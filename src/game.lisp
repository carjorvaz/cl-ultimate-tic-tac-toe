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

(defun outcome-p (object)
  "Return true when OBJECT is a board or game outcome."
  (or (null object)
      (player-p object)
      (eql object :draw)))

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

(defmacro do-legal-moves ((board cell game &optional result) &body body)
  "Evaluate BODY with BOARD and CELL bound to each legal move in GAME."
  (let ((game-var (gensym "GAME")))
    `(let ((,game-var ,game))
       (loop for ,board below +board-count+
             do (loop for ,cell below +board-count+
                      when (legal-move-p ,game-var ,board ,cell)
                        do (locally ,@body)))
       ,result)))

(defun first-legal-move (game)
  "Return the first legal BOARD and CELL for GAME, or NIL/NIL when none exist."
  (do-legal-moves (board cell game (values nil nil))
    (return-from first-legal-move (values board cell))))

(defun legal-move-count (game)
  "Return the number of currently legal moves in GAME."
  (let ((count 0))
    (do-legal-moves (board cell game count)
      (incf count))))

(defun expected-cell-array-p (object)
  (and (arrayp object)
       (= 2 (array-rank object))
       (= +board-count+ (array-dimension object 0))
       (= +board-count+ (array-dimension object 1))))

(defun expected-board-vector-p (object)
  (and (arrayp object)
       (= 1 (array-rank object))
       (= +board-count+ (array-dimension object 0))))

(defun occupied-cell-count (game)
  (loop for board below +board-count+
        sum (loop for cell below +board-count+
                  count (mark-at game board cell))))

(defun note-game-slot-violations (game violate)
  (let ((cells-valid-p (expected-cell-array-p (game-cells game)))
        (outcomes-valid-p
          (expected-board-vector-p (game-board-outcomes game))))
    (unless cells-valid-p
      (funcall violate :invalid-cells-array (game-cells game)))
    (unless outcomes-valid-p
      (funcall violate :invalid-board-outcomes-array
               (game-board-outcomes game)))
    (unless (player-p (game-next-player game))
      (funcall violate :invalid-next-player (game-next-player game)))
    (unless (and (integerp (game-move-count game))
                 (<= 0 (game-move-count game)
                     (* +board-count+ +board-count+)))
      (funcall violate :invalid-move-count (game-move-count game)))
    (unless (outcome-p (game-winner game))
      (funcall violate :invalid-winner (game-winner game)))
    (unless (or (null (game-active-board game))
                (valid-index-p (game-active-board game)))
      (funcall violate :invalid-active-board (game-active-board game)))
    (values cells-valid-p outcomes-valid-p)))

(defun note-game-cell-violations (game violate)
  (loop for board below +board-count+
        do (loop for cell below +board-count+
                 for mark = (mark-at game board cell)
                 unless (or (null mark) (player-p mark))
                   do (funcall violate :invalid-mark board cell mark)))
  (let ((occupied-cells (occupied-cell-count game)))
    (unless (= (game-move-count game) occupied-cells)
      (funcall violate :stale-move-count
               (game-move-count game)
               occupied-cells))))

(defun note-game-board-outcome-violations (game violate)
  (loop for board below +board-count+
        for outcome = (board-outcome game board)
        unless (outcome-p outcome)
          do (funcall violate :invalid-board-outcome board outcome)))

(defun note-derived-game-violations (game violate)
  (loop for board below +board-count+
        for recorded = (board-outcome game board)
        for actual = (local-board-outcome game board)
        unless (eql recorded actual)
          do (funcall violate :stale-board-outcome board recorded actual))
  (let ((actual-winner (global-outcome game)))
    (unless (eql (game-winner game) actual-winner)
      (funcall violate :stale-global-outcome
               (game-winner game)
               actual-winner)))
  (when (and (game-active-board game)
             (board-complete-p game (game-active-board game)))
    (funcall violate :closed-active-board (game-active-board game)))
  (when (and (game-winner game)
             (game-active-board game))
    (funcall violate :active-board-after-game-over
             (game-active-board game)))
  (when (and (null (game-winner game))
             (zerop (legal-move-count game)))
    (funcall violate :no-legal-moves-before-game-over)))

(defun game-invariant-violations (game)
  "Return internal consistency violations for GAME.

Each violation is a list whose first element is a keyword reason. A game built
only through PLAY-MOVE should have no violations."
  (let (violations)
    (flet ((violate (reason &rest details)
             (push (cons reason details) violations)))
      (if (not (game-p game))
          (violate :not-a-game game)
          (multiple-value-bind (cells-valid-p outcomes-valid-p)
              (note-game-slot-violations game #'violate)
            (when cells-valid-p
              (note-game-cell-violations game #'violate))
            (when outcomes-valid-p
              (note-game-board-outcome-violations game #'violate))
            (when (and cells-valid-p outcomes-valid-p)
              (note-derived-game-violations game #'violate)))))
    (nreverse violations)))

(defun valid-game-state-p (game)
  "Return whether GAME satisfies the internal invariants.

The second value is the list of invariant violations."
  (let ((violations (game-invariant-violations game)))
    (values (null violations) violations)))

(defun copy-game-cells (cells)
  (let ((copy (make-array (array-dimensions cells))))
    (loop for board below +board-count+
          do (loop for cell below +board-count+
                   do (setf (aref copy board cell)
                            (aref cells board cell))))
    copy))

(defun clone-game-state (game)
  "Return a fresh GAME object with copied mutable board arrays."
  (let ((clone (copy-game game)))
    (setf (game-cells clone)
          (copy-game-cells (game-cells game))
          (game-board-outcomes clone)
          (copy-seq (game-board-outcomes game)))
    clone))

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
    (if (game-winner game)
        (setf (game-active-board game) nil)
        (setf (game-active-board game) (unless (board-complete-p game cell)
                                         cell)
              (game-next-player game) (other-player player))))
  (values game t))

(defun game-over-p (game)
  "Return true when GAME has a winner or ended in a draw."
  (not (null (game-winner game))))
