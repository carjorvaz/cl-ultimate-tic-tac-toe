;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(asdf:defsystem "ultimate-tic-tac-toe"
  :description "Server-rendered Ultimate Tic Tac Toe with HTMX."
  :author "Contributors"
  :license "AGPL-3.0-or-later"
  :version "0.1.0"
  :depends-on ("coalton"
               "named-readtables"
               "clack"
               "lack"
               "lack/middleware/session"
               "ningle"
               "spinneret"
               "clack-handler-woo"
               "clack-handler-hunchentoot"
               "lack-session-store-dbi"
               "dbd-sqlite3"
               "hunchentoot"
               "bordeaux-threads"
               "ironclad"
               "sqlite")
  :components ((:module "src"
                :serial t
                :components ((:file "package")
                             (:file "rules")
                             (:file "game")
                             (:file "game-ai")
                             (:file "rooms")
                             (:file "rooms-memory")
                             (:file "rooms-sqlite")
                             (:file "web")
                             (:file "web-render")
                             (:file "web-handlers")))))

(asdf:defsystem "ultimate-tic-tac-toe/assets"
  :description "Asset build tooling for ultimate-tic-tac-toe."
  :author "Contributors"
  :license "AGPL-3.0-or-later"
  :depends-on ("lass"))

(asdf:defsystem "ultimate-tic-tac-toe/test"
  :description "Tests for ultimate-tic-tac-toe."
  :author "Contributors"
  :license "AGPL-3.0-or-later"
  :depends-on ("ultimate-tic-tac-toe" "fiveam" "usocket")
  :components ((:module "test"
                :serial t
                :components ((:file "package")
                             (:file "game-tests")
                             (:file "rules-tests")
                             (:file "room-tests")
                             (:file "web-tests"))))
  :perform (asdf:test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call :fiveam '#:run! :ultimate-tic-tac-toe)
               (error "The ultimate-tic-tac-toe test suite failed."))))
