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

(defparameter *cell-position-scores*
  #(20 0 20
    0 40 0
    20 0 20)
  "Tie-break scores for center, corner, and edge cells.")

(defconstant +tactical-global-win-score+ 10000
  "Score bonus for immediately winning the global game.")

(defconstant +tactical-local-win-score+ 5000
  "Score bonus for immediately winning a local board.")

(defconstant +tactical-local-block-score+ 2500
  "Score bonus for blocking an immediate local board win.")

(defconstant +tactical-open-choice-score+ 800
  "Score bonus for sending the opponent to an already completed board.")

(defconstant +hard-search-depth+ 2
  "Default number of plies searched by the hard deterministic opponent.")

(defconstant +hard-deeper-search-depth+ 3
  "Search depth used when branching is small enough to stay responsive.")

(defconstant +hard-deeper-search-max-legal-moves+ 9
  "Maximum current legal moves for the deeper hard search.")

(defconstant +hard-late-game-move-count+ 36
  "Move count where hard search may go deeper outside a single target board.")

(defconstant +hard-late-game-max-legal-moves+ 18
  "Maximum late-game legal moves for the deeper hard search.")

(defconstant +hard-search-cache-size+ 1024
  "Initial size for a per-move hard search transposition cache.")

(defconstant +hard-terminal-win-score+ 1000000
  "Search score for a forced global win.")

(defconstant +hard-owned-board-score+ 1200
  "Static score for owning a local board.")

(defconstant +hard-global-two-score+ 6000
  "Static score for threatening a global line.")

(defconstant +hard-global-one-score+ 450
  "Static score for owning one board in an open global line.")

(defconstant +hard-local-two-score+ 180
  "Static score for threatening a local board.")

(defconstant +hard-local-one-score+ 24
  "Static score for owning one mark in an open local line.")

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

(defmacro do-legal-moves ((board cell game &optional result) &body body)
  "Evaluate BODY with BOARD and CELL bound to each legal move in GAME."
  (let ((game-var (gensym "GAME")))
    `(let ((,game-var ,game))
       (loop for ,board below +board-count+
             do (loop for ,cell below +board-count+
                      when (legal-move-p ,game-var ,board ,cell)
                        do (progn ,@body)))
       ,result)))

(defun first-legal-move (game)
  "Return the first legal BOARD and CELL for GAME, or NIL/NIL when none exist."
  (do-legal-moves (board cell game (values nil nil))
    (return-from first-legal-move (values board cell))))

(defun legal-move-count (game)
  "Return the number of currently legal moves in GAME."
  (let ((count 0))
    (do-legal-moves (board cell game count)
      board
      cell
      (incf count))))

(defun local-board-outcome-with-mark (game board cell mark)
  (let ((previous-mark (aref (game-cells game) board cell)))
    (unwind-protect
         (progn
           (setf (aref (game-cells game) board cell) mark)
           (local-board-outcome game board))
      (setf (aref (game-cells game) board cell) previous-mark))))

(defun global-outcome-with-board-outcome (game board outcome)
  (let ((previous-outcome (aref (game-board-outcomes game) board)))
    (unwind-protect
         (progn
           (setf (aref (game-board-outcomes game) board) outcome)
           (global-outcome game))
      (setf (aref (game-board-outcomes game) board) previous-outcome))))

(defun target-board-complete-after-move-p (game board cell local-outcome)
  (if (= board cell)
      (not (null local-outcome))
      (board-complete-p game cell)))

(defun tactical-move-score (game board cell)
  (let* ((player (game-next-player game))
         (opponent (other-player player))
         (local-outcome (local-board-outcome-with-mark game board cell player))
         (global-outcome (global-outcome-with-board-outcome game
                                                            board
                                                            local-outcome))
         (opponent-local-outcome
           (local-board-outcome-with-mark game board cell opponent)))
    (flet ((bonus (condition score)
             (if condition score 0)))
      (+ (bonus (eql global-outcome player) +tactical-global-win-score+)
         (bonus (eql local-outcome player) +tactical-local-win-score+)
         (bonus (eql opponent-local-outcome opponent)
                +tactical-local-block-score+)
         (bonus (target-board-complete-after-move-p game
                                                    board
                                                    cell
                                                    local-outcome)
                +tactical-open-choice-score+)
         (aref *cell-position-scores* cell)))))

(defun best-tactical-move (game)
  "Return a deterministic tactical BOARD and CELL for GAME, or NIL/NIL."
  (let ((best-board nil)
        (best-cell nil)
        (best-score nil))
    (do-legal-moves (board cell game (values best-board best-cell))
      (let ((score (tactical-move-score game board cell)))
        (when (or (null best-score)
                  (> score best-score))
          (setf best-board board
                best-cell cell
                best-score score))))))

(defun copy-game-cells (cells)
  (let ((copy (make-array (array-dimensions cells))))
    (loop for board below +board-count+
          do (loop for cell below +board-count+
                   do (setf (aref copy board cell)
                            (aref cells board cell))))
    copy))

(defun clone-game-state (game)
  (let ((clone (copy-game game)))
    (setf (game-cells clone)
          (copy-game-cells (game-cells game))
          (game-board-outcomes clone)
          (copy-seq (game-board-outcomes game)))
    clone))

(defun game-after-move (game board cell)
  (let ((clone (clone-game-state game)))
    (multiple-value-bind (updated-game acceptedp rejection)
        (play-move clone board cell)
      (declare (ignore acceptedp rejection))
      updated-game)))

(defun line-control-score (values player opponent one-score two-score)
  (let ((player-count 0)
        (opponent-count 0)
        (blocked-p nil))
    (dolist (value values)
      (cond
        ((eql value player)
         (incf player-count))
        ((eql value opponent)
         (incf opponent-count))
        ((null value))
        (t
         (setf blocked-p t))))
    (cond
      (blocked-p 0)
      ((and (plusp player-count)
            (plusp opponent-count))
       0)
      ((= player-count 2) two-score)
      ((= opponent-count 2) (- two-score))
      ((= player-count 1) one-score)
      ((= opponent-count 1) (- one-score))
      (t 0))))

(defun board-outcome-line-values (game line)
  (mapcar (lambda (board)
            (board-outcome game board))
          line))

(defun local-mark-line-values (game board line)
  (mapcar (lambda (cell)
            (mark-at game board cell))
          line))

(defun global-line-evaluation (game player opponent)
  (loop for line in *winning-lines*
        sum (line-control-score (board-outcome-line-values game line)
                                player
                                opponent
                                +hard-global-one-score+
                                +hard-global-two-score+)))

(defun local-board-evaluation (game board player opponent)
  (let ((outcome (board-outcome game board)))
    (cond
      ((eql outcome player)
       +hard-owned-board-score+)
      ((eql outcome opponent)
       (- +hard-owned-board-score+))
      (outcome 0)
      (t
       (+ (loop for line in *winning-lines*
                sum (line-control-score (local-mark-line-values game board line)
                                        player
                                        opponent
                                        +hard-local-one-score+
                                        +hard-local-two-score+))
          (loop for cell below +board-count+
                for mark = (mark-at game board cell)
                sum (cond
                      ((eql mark player)
                       (aref *cell-position-scores* cell))
                      ((eql mark opponent)
                       (- (aref *cell-position-scores* cell)))
                      (t 0))))))))

(defun hard-static-evaluation (game player)
  (let ((opponent (other-player player)))
    (+ (global-line-evaluation game player opponent)
       (loop for board below +board-count+
             sum (local-board-evaluation game board player opponent)))))

(defun hard-terminal-score (game player ply)
  (let ((winner (game-winner game)))
    (cond
      ((null winner)
       (values 0 nil))
      ((eql winner player)
       (values (- +hard-terminal-win-score+ ply) t))
      ((eql winner (other-player player))
       (values (- ply +hard-terminal-win-score+) t))
      (t
       (values 0 t)))))

(defun hard-search-depth-for-position (game)
  "Return the default hard search depth for GAME's current branching factor."
  (let ((legal-moves (legal-move-count game)))
    (if (or (<= legal-moves +hard-deeper-search-max-legal-moves+)
            (and (>= (game-move-count game) +hard-late-game-move-count+)
                 (<= legal-moves +hard-late-game-max-legal-moves+)))
        +hard-deeper-search-depth+
        +hard-search-depth+)))

(defun game-cell-values (game)
  (loop for board below +board-count+
        append (loop for cell below +board-count+
                     collect (mark-at game board cell))))

(defun hard-search-cache-key (game player depth ply)
  (list player
        depth
        ply
        (game-next-player game)
        (game-active-board game)
        (game-winner game)
        (game-move-count game)
        (board-outcome-values game)
        (game-cell-values game)))

(defun compute-hard-search-score (game player depth ply cache)
  (multiple-value-bind (terminal-score terminalp)
      (hard-terminal-score game player ply)
    (cond
      (terminalp terminal-score)
      ((zerop depth)
       (hard-static-evaluation game player))
      (t
       (let ((best-score nil)
             (maximizing-p (eql (game-next-player game) player)))
         (do-legal-moves (board cell game)
           (let ((score (hard-search-score (game-after-move game board cell)
                                           player
                                           (1- depth)
                                           (1+ ply)
                                           cache)))
             (when (better-search-score-p score best-score maximizing-p)
               (setf best-score score))))
         (or best-score
             (hard-static-evaluation game player)))))))

(defun better-search-score-p (score best-score maximizing-p)
  (or (null best-score)
      (if maximizing-p
          (> score best-score)
          (< score best-score))))

(defun hard-search-score (game player depth ply &optional cache)
  (if cache
      (let ((key (hard-search-cache-key game player depth ply)))
        (multiple-value-bind (cached-score presentp)
            (gethash key cache)
          (if presentp
              cached-score
              (setf (gethash key cache)
                    (compute-hard-search-score game player depth ply cache)))))
      (compute-hard-search-score game player depth ply nil)))

(defun better-strategic-score-p (score tactical-score
                                 best-score best-tactical-score)
  (or (null best-score)
      (> score best-score)
      (and (= score best-score)
           (or (null best-tactical-score)
               (> tactical-score best-tactical-score)))))

(defun best-strategic-move (game &key depth)
  "Return a deterministic search-backed BOARD and CELL for GAME, or NIL/NIL."
  (let ((player (game-next-player game))
        (search-depth (max 0 (or depth
                                 (hard-search-depth-for-position game))))
        (cache (make-hash-table :test #'equal :size +hard-search-cache-size+))
        (best-board nil)
        (best-cell nil)
        (best-score nil)
        (best-tactical-score nil))
    (do-legal-moves (board cell game (values best-board best-cell))
      (let* ((score (hard-search-score (game-after-move game board cell)
                                       player
                                       (max 0 (1- search-depth))
                                       1
                                       cache))
             (tactical-score (tactical-move-score game board cell)))
        (when (better-strategic-score-p score
                                        tactical-score
                                        best-score
                                        best-tactical-score)
          (setf best-board board
                best-cell cell
                best-score score
                best-tactical-score tactical-score))))))

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

(defun play-first-legal-move (game)
  "Apply GAME's first legal move for the current player."
  (multiple-value-bind (board cell)
      (first-legal-move game)
    (if (and board cell)
        (play-move game board cell)
        (values game nil nil))))

(defun play-best-tactical-move (game)
  "Apply GAME's best deterministic tactical move for the current player."
  (multiple-value-bind (board cell)
      (best-tactical-move game)
    (if (and board cell)
        (play-move game board cell)
        (values game nil nil))))

(defun play-best-strategic-move (game)
  "Apply GAME's best deterministic search-backed move for the current player."
  (multiple-value-bind (board cell)
      (best-strategic-move game)
    (if (and board cell)
        (play-move game board cell)
        (values game nil nil))))

(defun game-over-p (game)
  "Return true when GAME has a winner or ended in a draw."
  (not (null (game-winner game))))
