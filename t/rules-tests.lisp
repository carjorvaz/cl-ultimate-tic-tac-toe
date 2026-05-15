;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(in-package #:ultimate-tic-tac-toe.tests)

(in-suite :ultimate-tic-tac-toe)

(defun marks-with-line (line &optional (mark :x))
  (loop for cell below +board-count+
        collect (and (member cell line :test #'=)
                     mark)))

(test coalton-local-rules-report-open-win-and-draw
  (is (null (local-board-outcome-symbols
             '(nil nil nil
               nil nil nil
               nil nil nil))))
  (is (eql :x (local-board-outcome-symbols
               '(:x :x :x
                 nil nil nil
                 nil nil nil))))
  (is (eql :o (local-board-outcome-symbols
               '(nil nil :o
                 nil :o nil
                 :o nil nil))))
  (is (eql :draw (local-board-outcome-symbols
                  '(:x :o :x
                    :x :o :o
                    :o :x :x)))))

(test coalton-global-rules-report-open-win-and-draw
  (is (null (global-outcome-symbols
             '(nil nil nil
               nil nil nil
               nil nil nil))))
  (is (eql :x (global-outcome-symbols
               '(:x :x :x
                 nil nil nil
                 nil nil nil))))
  (is (eql :o (global-outcome-symbols
               '(nil :o nil
                 nil :o nil
                 nil :o nil))))
  (is (eql :draw (global-outcome-symbols
                  '(:x :o :x
                    :x :o :o
                    :o :x :x)))))

(test coalton-winning-line-indexes-match-board-positions
  (loop for index from 0
        for line = (winning-line-positions index)
        while line
        count line into line-count
        do (is (= index
                  (winning-line-index-symbols (marks-with-line line :o))))
        finally
           (is (= 8 line-count))
           (is (null (winning-line-positions index)))))

(test coalton-rules-reject-malformed-input-as-open
  (is (null (local-board-outcome-symbols '(:x :x :x))))
  (is (null (global-outcome-symbols '(:x :x :x))))
  (is (= -1 (winning-line-index-symbols '(:x :x :x))))
  (is (null (local-board-outcome-symbols
             '(:x :x :x
               nil nil nil
               nil nil nil
               nil))))
  (is (null (global-outcome-symbols
             '(:x :x :x
               nil nil nil
               nil nil nil
               nil))))
  (is (= -1 (winning-line-index-symbols
             '(:x :x :x
               nil nil nil
               nil nil nil
               nil)))))
