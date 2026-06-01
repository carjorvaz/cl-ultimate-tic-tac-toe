;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(in-package #:ultimate-tic-tac-toe.game)

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
         (resulting-global-outcome
           (global-outcome-with-board-outcome game board local-outcome))
         (opponent-local-outcome
           (local-board-outcome-with-mark game board cell opponent)))
    (flet ((bonus (condition score)
             (if condition score 0)))
      (+ (bonus (eql resulting-global-outcome player)
                +tactical-global-win-score+)
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

(defun game-after-move (game board cell)
  (let ((clone (clone-game-state game)))
    (multiple-value-bind (updated-game acceptedp rejection)
        (play-move clone board cell)
      (declare (ignore acceptedp rejection))
      updated-game)))

(defun line-control-score (line-values player opponent one-score two-score)
  (let ((player-count 0)
        (opponent-count 0)
        (blocked-p nil))
    (dolist (value line-values)
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

(defun play-selected-move (game selector)
  (multiple-value-bind (board cell)
      (funcall selector game)
    (if (and board cell)
        (play-move game board cell)
        (values game nil nil))))

(defun play-first-legal-move (game)
  "Apply GAME's first legal move for the current player."
  (play-selected-move game #'first-legal-move))

(defun play-best-tactical-move (game)
  "Apply GAME's best deterministic tactical move for the current player."
  (play-selected-move game #'best-tactical-move))

(defun play-best-strategic-move (game)
  "Apply GAME's best deterministic search-backed move for the current player."
  (play-selected-move game #'best-strategic-move))
