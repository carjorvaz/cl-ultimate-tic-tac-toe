;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(in-package #:ultimate-tic-tac-toe.rooms)

(defconstant +room-code-length+ 6
  "Number of characters in a short shareable room code.")

(defparameter *room-code-alphabet* "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  "Readable room-code alphabet that avoids easily confused characters.")

(defstruct (memory-room-repository
            (:constructor %make-memory-room-repository))
  (rooms (make-hash-table :test #'equal))
  (lock (bordeaux-threads:make-lock "ultimate-tic-tac-toe-rooms"))
  (code-generator #'random-room-code))

(defstruct (sqlite-room-repository
            (:constructor %make-sqlite-room-repository))
  path
  (lock (bordeaux-threads:make-lock "ultimate-tic-tac-toe-sqlite-rooms"))
  (code-generator #'random-room-code)
  (busy-timeout 2000))

(defstruct (room-state
            (:constructor make-room-state (code))
            (:conc-name room-state-))
  code
  (game (make-game))
  x-token
  o-token
  (revision 0))

(defstruct (room-view
            (:constructor %make-room-view)
            (:conc-name room-view-))
  code
  game
  revision
  role
  mark
  x-seat-open-p
  o-seat-open-p)

(define-condition room-rejected (condition)
  ((code :initarg :code
         :reader room-rejected-code)
   (reason :initarg :reason
           :reader room-rejected-reason))
  (:report
   (lambda (condition stream)
     (format stream "Room ~S rejected request: ~S."
             (room-rejected-code condition)
             (room-rejected-reason condition)))))

(defun make-memory-room-repository (&key code-generator)
  "Return an in-memory room repository.

CODE-GENERATOR is injectable so tests can use deterministic short codes. The
repository owns a single lock around room lookup and mutation; this keeps the
room layer safe when web handlers race on seat claims or moves."
  (%make-memory-room-repository
   :code-generator (or code-generator #'random-room-code)))

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

(defun random-room-code ()
  (let* ((alphabet *room-code-alphabet*)
         (alphabet-length (length alphabet))
         (octets (ironclad:random-data +room-code-length+)))
    (coerce
     (loop for octet across octets
           collect (char alphabet (mod octet alphabet-length)))
     'string)))

(defmacro with-repository-lock ((repository) &body body)
  `(bordeaux-threads:with-lock-held ((memory-room-repository-lock ,repository))
     ,@body))

(defun copy-game-cells-for-room (cells)
  (let ((copy (make-array (list +board-count+ +board-count+))))
    (loop for board below +board-count+
          do (loop for cell below +board-count+
                   do (setf (aref copy board cell)
                            (aref cells board cell))))
    copy))

(defun clone-room-game (game)
  (make-game :cells (copy-game-cells-for-room (game-cells game))
             :board-outcomes (copy-seq (game-board-outcomes game))
             :next-player (game-next-player game)
             :active-board (game-active-board game)
             :winner (game-winner game)
             :move-count (game-move-count game)))

(defun clone-room-code (code)
  (copy-seq code))

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

(defun token= (left right)
  (and left
       right
       (equal left right)))

(defun private-token-p (token)
  (and (stringp token)
       (plusp (length token))))

(defun room-seat-token (room mark)
  (ecase mark
    (:x (room-state-x-token room))
    (:o (room-state-o-token room))))

(defun set-room-seat-token (room mark token)
  (ecase mark
    (:x (setf (room-state-x-token room) token))
    (:o (setf (room-state-o-token room) token))))

(defun room-mark-for-token (room token)
  (cond
    ((token= token (room-state-x-token room)) :x)
    ((token= token (room-state-o-token room)) :o)))

(defun room-view-for-token (room token)
  (let ((mark (room-mark-for-token room token)))
    (%make-room-view
     :code (clone-room-code (room-state-code room))
     :game (clone-room-game (room-state-game room))
     :revision (room-state-revision room)
     :role (if mark :player :watcher)
     :mark mark
     :x-seat-open-p (null (room-state-x-token room))
     :o-seat-open-p (null (room-state-o-token room)))))

(defun room-view-seat-open-p (view mark)
  "Return true when MARK's seat is open in VIEW."
  (ecase mark
    (:x (room-view-x-seat-open-p view))
    (:o (room-view-o-seat-open-p view))))

(defun room-rejection (code reason)
  (make-condition 'room-rejected
                  :code code
                  :reason reason))

(defun reject-room-request (room code token reason)
  (let ((rejection (room-rejection code reason)))
    (signal rejection)
    (values (when room
              (room-view-for-token room token))
            nil
            rejection)))

(defun repository-room (repository code)
  (gethash code (memory-room-repository-rooms repository)))

(defun generate-unique-room-code (repository)
  (loop repeat 64
        for code = (funcall (memory-room-repository-code-generator repository))
        unless (repository-room repository code)
          return code
        finally (error "Could not generate a unique room code.")))

(defun create-memory-room (repository)
  "Create a shareable room and return its watcher view."
  (with-repository-lock (repository)
    (let* ((code (generate-unique-room-code repository))
           (room (make-room-state code)))
      (setf (gethash code (memory-room-repository-rooms repository)) room)
      (room-view-for-token room nil))))

(defun view-memory-room (repository code token)
  "Return the room view for CODE as seen by TOKEN.

Unknown room codes are rejected without creating rooms. A missing or unrecognized
TOKEN receives a watcher view for existing rooms."
  (with-repository-lock (repository)
    (let ((room (repository-room repository code)))
      (if room
          (values (room-view-for-token room token) t nil)
          (reject-room-request nil code token :room-not-found)))))

(defun claim-memory-seat (repository code mark token)
  "Claim MARK in CODE with private TOKEN.

Returns three values: a ROOM-VIEW, acceptedp, and an optional ROOM-REJECTED
condition. Repeating the same claim with the same token is idempotent and does
not bump the room revision."
  (with-repository-lock (repository)
    (let ((room (repository-room repository code)))
      (cond
        ((null room)
         (reject-room-request nil code token :room-not-found))
        ((not (player-p mark))
         (reject-room-request room code token :invalid-seat))
        ((not (private-token-p token))
         (reject-room-request room code token :missing-token))
        ((eql mark (room-mark-for-token room token))
         (values (room-view-for-token room token) t nil))
        ((room-mark-for-token room token)
         (reject-room-request room code token :already-seated))
        ((room-seat-token room mark)
         (reject-room-request room code token :seat-occupied))
        (t
         (set-room-seat-token room mark token)
         (incf (room-state-revision room))
         (values (room-view-for-token room token) t nil))))))

(defun play-memory-room-move (repository code token revision board cell)
  "Apply BOARD/CELL for TOKEN in CODE when the submitted REVISION is current.

Returns three values: a ROOM-VIEW, acceptedp, and an optional ROOM-REJECTED
condition. Rejected moves leave the room game and revision unchanged."
  (with-repository-lock (repository)
    (let ((room (repository-room repository code)))
      (cond
        ((null room)
         (reject-room-request nil code token :room-not-found))
        ((null (room-mark-for-token room token))
         (reject-room-request room code token :watcher))
        ((not (eql revision (room-state-revision room)))
         (reject-room-request room code token :stale-revision))
        ((not (eql (room-mark-for-token room token)
                   (game-next-player (room-state-game room))))
         (reject-room-request room code token :wrong-turn))
        (t
         (multiple-value-bind (game acceptedp move-rejection)
             (play-move (room-state-game room) board cell)
           (declare (ignore game))
           (if acceptedp
               (progn
                 (incf (room-state-revision room))
                 (values (room-view-for-token room token) t nil))
               (reject-room-request room
                                    code
                                    token
                                    (move-rejected-reason move-rejection)))))))))

(defmacro with-sqlite-room-database ((db repository) &body body)
  `(sqlite:with-open-database (,db (sqlite-room-repository-path ,repository)
                                  :busy-timeout (sqlite-room-repository-busy-timeout
                                                 ,repository))
     (ensure-sqlite-room-schema ,db)
     ,@body))

(defmacro with-sqlite-room-repository ((db repository) &body body)
  `(bordeaux-threads:with-lock-held ((sqlite-room-repository-lock ,repository))
     (with-sqlite-room-database (,db ,repository)
       ,@body)))

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
    (values db))
  repository)

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
    (unless (= payload-version 1)
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

(defun insert-sqlite-room (db room)
  (let ((game (room-state-game room)))
    (sqlite:execute-non-query
     db
     "insert into rooms
        (code, revision, x_token, o_token, cells, board_outcomes,
         next_player, active_board, winner, move_count, payload_version)
      values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
     (room-state-code room)
     (room-state-revision room)
     (room-state-x-token room)
     (room-state-o-token room)
     (serialize-game-cells game)
     (serialize-board-outcomes game)
     (mark-token (game-next-player game))
     (game-active-board game)
     (outcome-token (game-winner game))
     (game-move-count game)
     1)))

(defun update-sqlite-room (db room expected-revision)
  (let ((game (room-state-game room)))
    (sqlite:execute-non-query
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
     (room-state-revision room)
     (room-state-x-token room)
     (room-state-o-token room)
     (serialize-game-cells game)
     (serialize-board-outcomes game)
     (mark-token (game-next-player game))
     (game-active-board game)
     (outcome-token (game-winner game))
     (game-move-count game)
     1
     (room-state-code room)
     expected-revision)
    (= 1 (sqlite-changes db))))

(defun generate-unique-sqlite-room-code (repository db)
  (loop repeat 64
        for code = (funcall (sqlite-room-repository-code-generator repository))
        unless (sqlite-room db code)
          return code
        finally (error "Could not generate a unique room code.")))

(defun create-sqlite-room (repository)
  (with-sqlite-room-repository (db repository)
    (sqlite:with-transaction db
      (let* ((code (generate-unique-sqlite-room-code repository db))
             (room (make-room-state code)))
        (insert-sqlite-room db room)
        (room-view-for-token room nil)))))

(defun view-sqlite-room (repository code token)
  (with-sqlite-room-repository (db repository)
    (let ((room (sqlite-room db code)))
      (if room
          (values (room-view-for-token room token) t nil)
          (reject-room-request nil code token :room-not-found)))))

(defun claim-sqlite-seat (repository code mark token)
  (with-sqlite-room-repository (db repository)
    (sqlite:with-transaction db
      (let ((room (sqlite-room db code)))
        (cond
          ((null room)
           (reject-room-request nil code token :room-not-found))
          ((not (player-p mark))
           (reject-room-request room code token :invalid-seat))
          ((not (private-token-p token))
           (reject-room-request room code token :missing-token))
          ((eql mark (room-mark-for-token room token))
           (values (room-view-for-token room token) t nil))
          ((room-mark-for-token room token)
           (reject-room-request room code token :already-seated))
          ((room-seat-token room mark)
           (reject-room-request room code token :seat-occupied))
          (t
            (let ((expected-revision (room-state-revision room)))
              (set-room-seat-token room mark token)
              (incf (room-state-revision room))
              (if (update-sqlite-room db room expected-revision)
                  (values (room-view-for-token room token) t nil)
                  (reject-room-request (sqlite-room db code)
                                       code
                                       token
                                       :stale-revision)))))))))

(defun play-sqlite-room-move (repository code token revision board cell)
  (with-sqlite-room-repository (db repository)
    (sqlite:with-transaction db
      (let ((room (sqlite-room db code)))
        (cond
          ((null room)
           (reject-room-request nil code token :room-not-found))
          ((null (room-mark-for-token room token))
           (reject-room-request room code token :watcher))
          ((not (eql revision (room-state-revision room)))
           (reject-room-request room code token :stale-revision))
          ((not (eql (room-mark-for-token room token)
                     (game-next-player (room-state-game room))))
           (reject-room-request room code token :wrong-turn))
          (t
            (multiple-value-bind (game acceptedp move-rejection)
                (play-move (room-state-game room) board cell)
              (declare (ignore game))
              (if acceptedp
                  (let ((expected-revision revision))
                    (incf (room-state-revision room))
                    (if (update-sqlite-room db room expected-revision)
                        (values (room-view-for-token room token) t nil)
                        (reject-room-request (sqlite-room db code)
                                             code
                                             token
                                             :stale-revision)))
                  (reject-room-request room
                                       code
                                       token
                                       (move-rejected-reason move-rejection))))))))))

(defun create-room (repository)
  (etypecase repository
    (memory-room-repository (create-memory-room repository))
    (sqlite-room-repository (create-sqlite-room repository))))

(defun view-room (repository code token)
  (etypecase repository
    (memory-room-repository (view-memory-room repository code token))
    (sqlite-room-repository (view-sqlite-room repository code token))))

(defun claim-seat (repository code mark token)
  (etypecase repository
    (memory-room-repository (claim-memory-seat repository code mark token))
    (sqlite-room-repository (claim-sqlite-seat repository code mark token))))

(defun play-room-move (repository code token revision board cell)
  (etypecase repository
    (memory-room-repository
     (play-memory-room-move repository code token revision board cell))
    (sqlite-room-repository
     (play-sqlite-room-move repository code token revision board cell))))
