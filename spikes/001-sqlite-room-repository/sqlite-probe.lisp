;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(require :asdf)
(asdf:load-system :sqlite)

(defun fail (label expected actual)
  (error "~A: expected ~S, got ~S" label expected actual))

(defun check-equal (label expected actual)
  (unless (equal expected actual)
    (fail label expected actual)))

(defun check-true (label value)
  (unless value
    (fail label t value)))

(defun scalar (db sql &rest parameters)
  (caar (apply #'sqlite:execute-to-list db sql parameters)))

(defun reset-db (path)
  (when (probe-file path)
    (delete-file path)))

(defun initialize-schema (db)
  (sqlite:execute-non-query db "pragma journal_mode = wal")
  (sqlite:execute-non-query db "pragma foreign_keys = on")
  (sqlite:execute-non-query
   db
   "create table if not exists rooms (
      code text primary key,
      revision integer not null,
      payload text not null,
      updated_at text not null default current_timestamp
    )")
  (sqlite:execute-non-query
   db
   "create index if not exists rooms_revision_idx on rooms (code, revision)"))

(defun optimistic-update-room (db code expected-revision payload)
  (sqlite:with-transaction db
    (sqlite:execute-non-query
     db
     "update rooms
         set revision = revision + 1,
             payload = ?,
             updated_at = current_timestamp
       where code = ? and revision = ?"
     payload code expected-revision)
    (scalar db "select changes()")))

(defun main ()
  (let* ((path (or (second sb-ext:*posix-argv*)
                   "/tmp/uttt-sqlite-room-spike.sqlite3"))
         (payload-v1 "(:version 1 :game (:moves 0))")
         (payload-v2 "(:version 1 :game (:moves 1))"))
    (reset-db path)

    (sqlite:with-open-database (db path :busy-timeout 2000)
      (initialize-schema db)
      (sqlite:execute-non-query
       db
       "insert into rooms (code, revision, payload) values (?, ?, ?)"
       "ROOM42" 0 payload-v1)
      (check-equal "inserted row"
                   '(("ROOM42" 0 "(:version 1 :game (:moves 0))"))
                   (sqlite:execute-to-list
                    db
                    "select code, revision, payload from rooms where code = ?"
                    "ROOM42"))
      (handler-case
          (progn
            (sqlite:execute-non-query
             db
             "insert into rooms (code, revision, payload) values (?, ?, ?)"
             "ROOM42" 0 payload-v1)
            (fail "duplicate room constraint" 'sqlite:sqlite-constraint-error :no-error))
        (sqlite:sqlite-constraint-error ()
          (format t "duplicate room constraint raised sqlite-constraint-error~%")))
      (check-equal "accepted revision update" 1
                   (optimistic-update-room db "ROOM42" 0 payload-v2))
      (check-equal "stale revision update rejected by row count" 0
                   (optimistic-update-room db "ROOM42" 0 "stale")))

    (sqlite:with-open-database (db path :busy-timeout 2000)
      (initialize-schema db)
      (check-equal "row survived reopen"
                   '(("ROOM42" 1 "(:version 1 :game (:moves 1))"))
                   (sqlite:execute-to-list
                    db
                    "select code, revision, payload from rooms where code = ?"
                    "ROOM42"))
      (handler-case
          (sqlite:with-transaction db
            (sqlite:execute-non-query
             db
             "insert into rooms (code, revision, payload) values (?, ?, ?)"
             "ROLLBK" 0 payload-v1)
            (error "force rollback"))
        (error ()
          (format t "transaction rollback path exercised~%")))
      (check-equal "rollback removed row"
                   0
                   (scalar db "select count(*) from rooms where code = ?" "ROLLBK")))

    (format t "SQLite room repository spike validated at ~A~%" path)))

(main)
