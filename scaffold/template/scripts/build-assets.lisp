;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(load (merge-pathnames "asset-tools.lisp"
                       (make-pathname :name nil :type nil :defaults *load-truename*)))

(app.asset-tools:build-assets)
