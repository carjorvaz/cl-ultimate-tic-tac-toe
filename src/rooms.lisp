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

(defun create-room (repository)
  "Create a shareable room and return its watcher view."
  (with-repository-lock (repository)
    (let* ((code (generate-unique-room-code repository))
           (room (make-room-state code)))
      (setf (gethash code (memory-room-repository-rooms repository)) room)
      (room-view-for-token room nil))))

(defun view-room (repository code token)
  "Return the room view for CODE as seen by TOKEN.

Unknown room codes are rejected without creating rooms. A missing or unrecognized
TOKEN receives a watcher view for existing rooms."
  (with-repository-lock (repository)
    (let ((room (repository-room repository code)))
      (if room
          (values (room-view-for-token room token) t nil)
          (reject-room-request nil code token :room-not-found)))))

(defun claim-seat (repository code mark token)
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

(defun play-room-move (repository code token revision board cell)
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
