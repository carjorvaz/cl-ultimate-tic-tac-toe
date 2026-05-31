;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(in-package #:app.tests)

(def-suite :app)
(in-suite :app)

(test domain-copy-is-stable
  (is (string= "Common Lisp Web App" (app-title)))
  (is (search "server-rendered" (app-summary)))
  (is (= 3 (length (status-lines)))))
