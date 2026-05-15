;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(require :asdf)

(defun script-directory ()
  (make-pathname :name nil
                 :type nil
                 :defaults *load-truename*))

(defparameter *project-root*
  (truename (merge-pathnames "../" (script-directory))))

(pushnew *project-root* asdf:*central-registry* :test #'equal)

(asdf:load-system :ultimate-tic-tac-toe/test)

(defun stop-test-server ()
  (when (find-package :ultimate-tic-tac-toe.web)
    (uiop:symbol-call :ultimate-tic-tac-toe.web '#:stop)))

(let ((passedp nil))
  (unwind-protect
       (setf passedp (uiop:symbol-call :fiveam '#:run! :ultimate-tic-tac-toe))
    (stop-test-server))
  (uiop:quit (if passedp 0 1)))
