;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(asdf:defsystem "app"
  :description "Server-rendered Common Lisp web app scaffold."
  :author "Contributors"
  :license "AGPL-3.0-or-later"
  :version "0.1.0"
  :depends-on ("clack"
               "lack"
               "ningle"
               "spinneret"
               "clack-handler-woo"
               "clack-handler-hunchentoot"
               "hunchentoot")
  :components ((:module "src"
                :serial t
                :components ((:file "package")
                             (:file "domain")
                             (:file "web")))))

(asdf:defsystem "app/assets"
  :description "Asset build tooling for the app scaffold."
  :author "Contributors"
  :license "AGPL-3.0-or-later"
  :depends-on ("lass"))

(asdf:defsystem "app/test"
  :description "Tests for the app scaffold."
  :author "Contributors"
  :license "AGPL-3.0-or-later"
  :depends-on ("app" "fiveam")
  :components ((:module "t"
                :serial t
                :components ((:file "package")
                             (:file "domain-tests")
                             (:file "web-tests"))))
  :perform (asdf:test-op (operation component)
             (declare (ignore operation component))
             (unless (uiop:symbol-call :fiveam '#:run! :app)
               (error "The app test suite failed."))))
