;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(load (merge-pathnames "asset-tools.lisp"
                       (make-pathname :name nil
                                      :type nil
                                      :defaults *load-truename*)))

(ultimate-tic-tac-toe.asset-tools:build-assets)
