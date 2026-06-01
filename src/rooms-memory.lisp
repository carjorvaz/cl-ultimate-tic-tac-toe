;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(in-package #:ultimate-tic-tac-toe.rooms)

(defstruct (memory-room-repository
            (:constructor %make-memory-room-repository))
  (rooms (make-hash-table :test #'equal))
  (lock (bordeaux-threads:make-lock "ultimate-tic-tac-toe-rooms"))
  (code-generator #'random-room-code))

(defun make-memory-room-repository (&key code-generator)
  "Return an in-memory room repository.

CODE-GENERATOR is injectable so tests can use deterministic short codes. The
repository owns a single lock around room lookup and mutation; this keeps the
room layer safe when web handlers race on seat claims or moves."
  (%make-memory-room-repository
   :code-generator (or code-generator #'random-room-code)))

(defmacro with-memory-room-repository-lock ((repository) &body body)
  (let ((repository-var (gensym "REPOSITORY"))
        (lock-var (gensym "LOCK")))
    `(let* ((,repository-var ,repository)
            (,lock-var (memory-room-repository-lock ,repository-var)))
       (bordeaux-threads:with-lock-held (,lock-var)
         ,@body))))

(defun memory-room (repository code)
  (gethash code (memory-room-repository-rooms repository)))

(defun generate-unique-memory-room-code (repository)
  (generate-unique-room-code
   (memory-room-repository-code-generator repository)
   (lambda (code)
     (memory-room repository code))))

(defun commit-memory-room (room expected-revision)
  (declare (ignore expected-revision))
  (values t room))

(defmethod create-room ((repository memory-room-repository))
  (with-memory-room-repository-lock (repository)
    (let* ((code (generate-unique-memory-room-code repository))
           (room (make-room-state code)))
      (setf (gethash code (memory-room-repository-rooms repository)) room)
      (room-view-for-token room nil))))

(defmethod view-room ((repository memory-room-repository) code token)
  (with-memory-room-repository-lock (repository)
    (let ((room (memory-room repository code)))
      (if room
          (values (room-view-for-token room token) t nil)
          (reject-room-request nil code token :room-not-found)))))

(defmethod claim-seat ((repository memory-room-repository) code mark token)
  (with-memory-room-repository-lock (repository)
    (let ((room (memory-room repository code)))
      (if room
          (claim-room-seat-in-room room code mark token #'commit-memory-room)
          (reject-room-request nil code token :room-not-found)))))

(defmethod play-room-move ((repository memory-room-repository)
                           code token revision board cell)
  (with-memory-room-repository-lock (repository)
    (let ((room (memory-room repository code)))
      (if room
          (play-room-move-in-room room
                                  code
                                  token
                                  revision
                                  board
                                  cell
                                  #'commit-memory-room)
          (reject-room-request nil code token :room-not-found)))))
