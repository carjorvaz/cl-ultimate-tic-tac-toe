;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(in-package #:ultimate-tic-tac-toe.rooms)

(defconstant +room-code-length+ 6
  "Number of characters in a short shareable room code.")

(defparameter *room-code-alphabet* "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  "Readable room-code alphabet that avoids easily confused characters.")

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

(defgeneric create-room (repository)
  (:documentation "Create a shareable room in REPOSITORY and return its watcher view."))

(defgeneric view-room (repository code token)
  (:documentation "Return CODE's room view for TOKEN, or reject an unknown room."))

(defgeneric claim-seat (repository code mark token)
  (:documentation "Claim MARK in CODE with private TOKEN.

Returns three values: a ROOM-VIEW, acceptedp, and an optional ROOM-REJECTED
condition. Repeating the same claim with the same token is idempotent and does
not bump the room revision."))

(defgeneric play-room-move (repository code token revision board cell)
  (:documentation "Apply BOARD/CELL for TOKEN in CODE when REVISION is current.

Returns three values: a ROOM-VIEW, acceptedp, and an optional ROOM-REJECTED
condition. Rejected moves leave the room game and revision unchanged."))

(defun random-room-code ()
  (let* ((alphabet *room-code-alphabet*)
         (alphabet-length (length alphabet))
         (octets (ironclad:random-data +room-code-length+)))
    (coerce
     (loop for octet across octets
           collect (char alphabet (mod octet alphabet-length)))
     'string)))

(defun generate-unique-room-code (code-generator room-exists-p)
  (loop repeat 64
        for code = (funcall code-generator)
        unless (funcall room-exists-p code)
          return code
        finally (error "Could not generate a unique room code.")))

(defun clone-room-game (game)
  (clone-game-state game))

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

(defun (setf room-seat-token) (token room mark)
  (ecase mark
    (:x (setf (room-state-x-token room) token))
    (:o (setf (room-state-o-token room) token))))

(defun room-mark-for-token (room token)
  (cond
    ((token= token (room-state-x-token room)) :x)
    ((token= token (room-state-o-token room)) :o)))

(defun room-seat-claim-status (room mark token token-mark)
  (cond
    ((not (player-p mark)) :invalid-seat)
    ((not (private-token-p token)) :missing-token)
    ((eql mark token-mark) :already-claimed)
    (token-mark :already-seated)
    ((room-seat-token room mark) :seat-occupied)))

(defun claim-room-seat-in-state (room mark token)
  (setf (room-seat-token room mark) token)
  (incf (room-state-revision room))
  room)

(defun room-move-rejection-reason (room token-mark revision)
  (cond
    ((null token-mark) :watcher)
    ((not (eql revision (room-state-revision room))) :stale-revision)
    ((not (eql token-mark (game-next-player (room-state-game room))))
     :wrong-turn)))

(defun play-room-state-move (room board cell)
  (multiple-value-bind (game acceptedp move-rejection)
      (play-move (room-state-game room) board cell)
    (declare (ignore game))
    (if acceptedp
        (progn
          (incf (room-state-revision room))
          nil)
        (move-rejected-reason move-rejection))))

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

(defun accept-room-request (room token)
  (values (room-view-for-token room token) t nil))

(defun finish-room-mutation (room token expected-revision commit)
  (multiple-value-bind (committedp current-room)
      (funcall commit room expected-revision)
    (if committedp
        (accept-room-request room token)
        (reject-room-request current-room
                             (room-state-code room)
                             token
                             :stale-revision))))

(defun claim-room-seat-in-room (room code mark token commit)
  (let* ((token-mark (room-mark-for-token room token))
         (claim-status (room-seat-claim-status room mark token token-mark)))
    (cond
      ((eql claim-status :already-claimed)
       (accept-room-request room token))
      (claim-status
       (reject-room-request room code token claim-status))
      (t
       (let ((expected-revision (room-state-revision room)))
         (claim-room-seat-in-state room mark token)
         (finish-room-mutation room token expected-revision commit))))))

(defun play-room-move-in-room (room code token revision board cell commit)
  (let* ((token-mark (room-mark-for-token room token))
         (authorization-rejection
           (room-move-rejection-reason room token-mark revision)))
    (cond
      (authorization-rejection
       (reject-room-request room code token authorization-rejection))
      (t
       (let ((move-rejection-reason (play-room-state-move room board cell)))
         (if move-rejection-reason
             (reject-room-request room code token move-rejection-reason)
             (finish-room-mutation room token revision commit)))))))
