;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(in-package #:ultimate-tic-tac-toe.rooms)

(defconstant +sqlite-room-payload-version+ 1
  "Version number for rows stored in the SQLite room repository.")

(defstruct (sqlite-room-repository
            (:constructor %make-sqlite-room-repository))
  path
  (lock (bordeaux-threads:make-lock "ultimate-tic-tac-toe-sqlite-rooms"))
  (code-generator #'random-room-code)
  (busy-timeout 2000))

(defun make-sqlite-room-repository (path &key code-generator (busy-timeout 2000))
  "Return a SQLite-backed room repository stored at PATH."
  (let ((repository
          (%make-sqlite-room-repository
           :path (etypecase path
                   (string path)
                   (pathname (namestring path)))
           :code-generator (or code-generator #'random-room-code)
           :busy-timeout busy-timeout)))
    (initialize-sqlite-room-repository repository)
    repository))

(defmacro with-sqlite-room-database ((db repository) &body body)
  (let ((repository-var (gensym "REPOSITORY"))
        (path-var (gensym "PATH"))
        (busy-timeout-var (gensym "BUSY-TIMEOUT")))
    `(let* ((,repository-var ,repository)
            (,path-var (sqlite-room-repository-path ,repository-var))
            (,busy-timeout-var
              (sqlite-room-repository-busy-timeout ,repository-var)))
       (sqlite:with-open-database (,db ,path-var
                                    :busy-timeout ,busy-timeout-var)
         (ensure-sqlite-room-schema ,db)
         ,@body))))

(defmacro with-sqlite-room-repository ((db repository) &body body)
  (let ((repository-var (gensym "REPOSITORY"))
        (lock-var (gensym "LOCK")))
    `(let* ((,repository-var ,repository)
            (,lock-var (sqlite-room-repository-lock ,repository-var)))
       (bordeaux-threads:with-lock-held (,lock-var)
         (with-sqlite-room-database (,db ,repository-var)
           ,@body)))))

(defun ensure-sqlite-room-schema (db)
  (sqlite:execute-non-query db "pragma foreign_keys = on")
  (sqlite:execute-non-query db "pragma journal_mode = wal")
  (sqlite:execute-non-query
   db
   "create table if not exists rooms (
      code text primary key,
      revision integer not null,
      x_token text,
      o_token text,
      cells text not null,
      board_outcomes text not null,
      next_player text not null,
      active_board integer,
      winner text,
      move_count integer not null,
      payload_version integer not null
    )"))

(defun initialize-sqlite-room-repository (repository)
  (with-sqlite-room-database (db repository)
    (values))
  repository)

(defun mark-token (mark)
  (ecase mark
    (:x "x")
    (:o "o")
    ((nil) nil)))

(defun outcome-token (outcome)
  (ecase outcome
    (:x "x")
    (:o "o")
    (:draw "draw")
    ((nil) nil)))

(defun token-mark (token)
  (cond
    ((null token) nil)
    ((string= token "x") :x)
    ((string= token "o") :o)
    (t (error "Unknown player mark token ~S." token))))

(defun token-outcome (token)
  (cond
    ((null token) nil)
    ((string= token "x") :x)
    ((string= token "o") :o)
    ((string= token "draw") :draw)
    (t (error "Unknown outcome token ~S." token))))

(defun mark-character (mark)
  (ecase mark
    (:x #\X)
    (:o #\O)
    ((nil) #\.)))

(defun outcome-character (outcome)
  (ecase outcome
    (:x #\X)
    (:o #\O)
    (:draw #\D)
    ((nil) #\.)))

(defun character-mark (character)
  (ecase character
    (#\X :x)
    (#\O :o)
    (#\. nil)))

(defun character-outcome (character)
  (ecase character
    (#\X :x)
    (#\O :o)
    (#\D :draw)
    (#\. nil)))

(defun serialize-game-cells (game)
  (with-output-to-string (stream)
    (loop for board below +board-count+
          do (loop for cell below +board-count+
                   do (write-char (mark-character (mark-at game board cell))
                                  stream)))))

(defun deserialize-game-cells (string)
  (unless (= (length string) (* +board-count+ +board-count+))
    (error "Cell payload has unexpected length ~D." (length string)))
  (let ((cells (make-array (list +board-count+ +board-count+))))
    (loop for board below +board-count+
          do (loop for cell below +board-count+
                   for index = (+ (* board +board-count+) cell)
                   do (setf (aref cells board cell)
                            (character-mark (char string index)))))
    cells))

(defun serialize-board-outcomes (game)
  (with-output-to-string (stream)
    (loop for board below +board-count+
          do (write-char (outcome-character (aref (game-board-outcomes game)
                                                  board))
                         stream))))

(defun deserialize-board-outcomes (string)
  (unless (= (length string) +board-count+)
    (error "Board outcome payload has unexpected length ~D." (length string)))
  (let ((outcomes (make-array +board-count+)))
    (loop for board below +board-count+
          do (setf (aref outcomes board)
                   (character-outcome (char string board))))
    outcomes))

(defun sqlite-changes (db)
  (caar (sqlite:execute-to-list db "select changes()")))

(defun sqlite-room-row (db code)
  (first
   (sqlite:execute-to-list
    db
    "select code,
            revision,
            x_token,
            o_token,
            cells,
            board_outcomes,
            next_player,
            active_board,
            winner,
            move_count,
            payload_version
       from rooms
      where code = ?"
    code)))

(defun game-from-sqlite-row (cells board-outcomes next-player active-board winner move-count)
  (make-game :cells (deserialize-game-cells cells)
             :board-outcomes (deserialize-board-outcomes board-outcomes)
             :next-player (token-mark next-player)
             :active-board active-board
             :winner (token-outcome winner)
             :move-count move-count))

(defun room-state-from-sqlite-row (row)
  (destructuring-bind (code revision x-token o-token cells board-outcomes
                       next-player active-board winner move-count payload-version)
      row
    (unless (= payload-version +sqlite-room-payload-version+)
      (error "Unsupported room payload version ~D." payload-version))
    (let ((room (make-room-state code)))
      (setf (room-state-revision room) revision
            (room-state-x-token room) x-token
            (room-state-o-token room) o-token
            (room-state-game room)
            (game-from-sqlite-row cells
                                  board-outcomes
                                  next-player
                                  active-board
                                  winner
                                  move-count))
      room)))

(defun sqlite-room (db code)
  (let ((row (sqlite-room-row db code)))
    (when row
      (room-state-from-sqlite-row row))))

(defun sqlite-room-values (room)
  (let ((game (room-state-game room)))
    (list (room-state-revision room)
          (room-state-x-token room)
          (room-state-o-token room)
          (serialize-game-cells game)
          (serialize-board-outcomes game)
          (mark-token (game-next-player game))
          (game-active-board game)
          (outcome-token (game-winner game))
          (game-move-count game)
          +sqlite-room-payload-version+)))

(defun insert-sqlite-room (db room)
  (apply #'sqlite:execute-non-query
         db
         "insert into rooms
            (code, revision, x_token, o_token, cells, board_outcomes,
             next_player, active_board, winner, move_count, payload_version)
          values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
         (room-state-code room)
         (sqlite-room-values room)))

(defun update-sqlite-room (db room expected-revision)
  (apply #'sqlite:execute-non-query
         db
         "update rooms
             set revision = ?,
                 x_token = ?,
                 o_token = ?,
                 cells = ?,
                 board_outcomes = ?,
                 next_player = ?,
                 active_board = ?,
                 winner = ?,
                 move_count = ?,
                 payload_version = ?
           where code = ? and revision = ?"
         (append (sqlite-room-values room)
                 (list (room-state-code room) expected-revision)))
  (= 1 (sqlite-changes db)))

(defun generate-unique-sqlite-room-code (repository db)
  (generate-unique-room-code
   (sqlite-room-repository-code-generator repository)
   (lambda (code)
     (sqlite-room db code))))

(defun commit-sqlite-room (db code)
  (lambda (room expected-revision)
    (if (update-sqlite-room db room expected-revision)
        (values t room)
        (values nil (sqlite-room db code)))))

(defmethod create-room ((repository sqlite-room-repository))
  (with-sqlite-room-repository (db repository)
    (sqlite:with-transaction db
      (let* ((code (generate-unique-sqlite-room-code repository db))
             (room (make-room-state code)))
        (insert-sqlite-room db room)
        (room-view-for-token room nil)))))

(defmethod view-room ((repository sqlite-room-repository) code token)
  (with-sqlite-room-repository (db repository)
    (let ((room (sqlite-room db code)))
      (if room
          (values (room-view-for-token room token) t nil)
          (reject-room-request nil code token :room-not-found)))))

(defmethod claim-seat ((repository sqlite-room-repository) code mark token)
  (with-sqlite-room-repository (db repository)
    (sqlite:with-transaction db
      (let ((room (sqlite-room db code)))
        (if room
            (claim-room-seat-in-room room
                                     code
                                     mark
                                     token
                                     (commit-sqlite-room db code))
            (reject-room-request nil code token :room-not-found))))))

(defmethod play-room-move ((repository sqlite-room-repository)
                           code token revision board cell)
  (with-sqlite-room-repository (db repository)
    (sqlite:with-transaction db
      (let ((room (sqlite-room db code)))
        (if room
            (play-room-move-in-room room
                                    code
                                    token
                                    revision
                                    board
                                    cell
                                    (commit-sqlite-room db code))
            (reject-room-request nil code token :room-not-found))))))
