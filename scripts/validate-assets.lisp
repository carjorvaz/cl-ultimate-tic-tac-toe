;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(load (merge-pathnames "asset-tools.lisp"
                       (make-pathname :name nil
                                      :type nil
                                      :defaults *load-truename*)))

(defun main ()
  (let* ((target (ultimate-tic-tac-toe.asset-tools:stylesheet-target-path))
         (expected (ultimate-tic-tac-toe.asset-tools:generated-stylesheet))
         (actual (and (probe-file target)
                      (uiop:read-file-string target))))
    (cond
      ((null actual)
       (format t "~&Asset validation failed: static/style.css is missing.~%")
       (uiop:quit 1))
      ((not (string= expected actual))
       (format t "~&Asset validation failed: static/style.css is stale.~%")
       (format t "Run `sbcl --script scripts/build-assets.lisp`.~%")
       (uiop:quit 1))
      (t
       (format t "~&Asset validation passed.~%")
       (uiop:quit 0)))))

(main)
