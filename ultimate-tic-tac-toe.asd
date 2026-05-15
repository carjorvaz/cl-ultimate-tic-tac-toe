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
               "hunchentoot"
               "bordeaux-threads"
               "ironclad")
  :components ((:module "src"
                :serial t
                :components ((:file "package")
                             (:file "rules")
                             (:file "game")
                             (:file "web")))))

(asdf:defsystem "ultimate-tic-tac-toe/test"
  :description "Tests for ultimate-tic-tac-toe."
  :author "Contributors"
  :license "AGPL-3.0-or-later"
  :depends-on ("ultimate-tic-tac-toe" "fiveam" "usocket")
  :components ((:module "t"
                :serial t
                :components ((:file "package")
                             (:file "game-tests")
                             (:file "rules-tests")
                             (:file "web-tests"))))
  :perform (asdf:test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call :fiveam '#:run! :ultimate-tic-tac-toe)
               (error "The ultimate-tic-tac-toe test suite failed."))))
