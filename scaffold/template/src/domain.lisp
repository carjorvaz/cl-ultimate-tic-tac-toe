;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(in-package #:app.domain)

(defun app-title ()
  "Common Lisp Web App")

(defun app-summary ()
  "A tiny server-rendered scaffold with tests, docs, assets, and browser smoke.")

(defun status-lines ()
  (list "Domain logic is independent from HTTP."
        "HTML is rendered on the server."
        "Validation scripts are part of the app contract."))
