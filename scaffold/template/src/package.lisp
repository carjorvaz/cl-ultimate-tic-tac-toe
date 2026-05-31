;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(defpackage #:app.domain
  (:use #:cl)
  (:export #:app-title #:app-summary #:status-lines))

(defpackage #:app.web
  (:use #:cl)
  (:import-from #:app.domain #:app-title #:app-summary #:status-lines)
  (:export #:start #:stop #:server-port))
