;;;; SPDX-License-Identifier: AGPL-3.0-or-later

(cl:in-package #:ultimate-tic-tac-toe.rules)

(named-readtables:in-readtable coalton:coalton)

(coalton-toplevel
  (repr :enum)
  (define-type Mark
    EmptyMark
    XMark
    OMark)

  (repr :enum)
  (define-type Outcome
    OpenOutcome
    XOutcome
    OOutcome
    DrawOutcome)

  (declare open-symbol sym:Symbol)
  (define open-symbol
    (lisp sym:Symbol ()
      cl:nil))

  (declare x-symbol sym:Symbol)
  (define x-symbol
    (lisp sym:Symbol ()
      ':x))

  (declare o-symbol sym:Symbol)
  (define o-symbol
    (lisp sym:Symbol ()
      ':o))

  (declare draw-symbol sym:Symbol)
  (define draw-symbol
    (lisp sym:Symbol ()
      ':draw))

  (declare symbol->mark (sym:Symbol -> Mark))
  (define (symbol->mark mark)
    (cond
      ((== mark x-symbol) XMark)
      ((== mark o-symbol) OMark)
      (True EmptyMark)))

  (declare symbol->outcome (sym:Symbol -> Outcome))
  (define (symbol->outcome outcome)
    (cond
      ((== outcome x-symbol) XOutcome)
      ((== outcome o-symbol) OOutcome)
      ((== outcome draw-symbol) DrawOutcome)
      (True OpenOutcome)))

  (declare mark->outcome (Mark -> Outcome))
  (define (mark->outcome mark)
    (match mark
      ((XMark) XOutcome)
      ((OMark) OOutcome)
      ((EmptyMark) OpenOutcome)))

  (declare outcome->mark (Outcome -> Mark))
  (define (outcome->mark outcome)
    (match outcome
      ((XOutcome) XMark)
      ((OOutcome) OMark)
      (_ EmptyMark)))

  (declare outcome->symbol (Outcome -> sym:Symbol))
  (define (outcome->symbol outcome)
    (match outcome
      ((XOutcome) x-symbol)
      ((OOutcome) o-symbol)
      ((DrawOutcome) draw-symbol)
      ((OpenOutcome) open-symbol)))

  (declare player-mark? (Mark -> Boolean))
  (define (player-mark? mark)
    (match mark
      ((XMark) True)
      ((OMark) True)
      ((EmptyMark) False)))

  (declare same-mark? (Mark -> Mark -> Boolean))
  (define (same-mark? left right)
    (match (Tuple left right)
      ((Tuple (XMark) (XMark)) True)
      ((Tuple (OMark) (OMark)) True)
      ((Tuple (EmptyMark) (EmptyMark)) True)
      (_ False)))

  (declare line-winner? (Mark -> Mark -> Mark -> Boolean))
  (define (line-winner? a b c)
    (and (player-mark? a)
         (same-mark? a b)
         (same-mark? a c)))

  (declare all-cells-filled? (Mark -> Mark -> Mark
                                   -> Mark -> Mark -> Mark
                                   -> Mark -> Mark -> Mark
                                   -> Boolean))
  (define (all-cells-filled? a b c d e f g h i)
    (and (player-mark? a)
         (player-mark? b)
         (player-mark? c)
         (player-mark? d)
         (player-mark? e)
         (player-mark? f)
         (player-mark? g)
         (player-mark? h)
         (player-mark? i)))

  (declare closed-outcome? (Outcome -> Boolean))
  (define (closed-outcome? outcome)
    (match outcome
      ((OpenOutcome) False)
      (_ True)))

  (declare all-boards-closed? (Outcome -> Outcome -> Outcome
                                       -> Outcome -> Outcome -> Outcome
                                       -> Outcome -> Outcome -> Outcome
                                       -> Boolean))
  (define (all-boards-closed? a b c d e f g h i)
    (and (closed-outcome? a)
         (closed-outcome? b)
         (closed-outcome? c)
         (closed-outcome? d)
         (closed-outcome? e)
         (closed-outcome? f)
         (closed-outcome? g)
         (closed-outcome? h)
         (closed-outcome? i)))

  (declare winning-player9 (Mark -> Mark -> Mark
                                 -> Mark -> Mark -> Mark
                                 -> Mark -> Mark -> Mark
                                 -> Mark))
  (define (winning-player9 a b c d e f g h i)
    (cond
      ((line-winner? a b c) a)
      ((line-winner? d e f) d)
      ((line-winner? g h i) g)
      ((line-winner? a d g) a)
      ((line-winner? b e h) b)
      ((line-winner? c f i) c)
      ((line-winner? a e i) a)
      ((line-winner? c e g) c)
      (True EmptyMark)))

  (declare winning-line-index9 (Mark -> Mark -> Mark
                                     -> Mark -> Mark -> Mark
                                     -> Mark -> Mark -> Mark
                                     -> Integer))
  (define (winning-line-index9 a b c d e f g h i)
    (cond
      ((line-winner? a b c) 0)
      ((line-winner? d e f) 1)
      ((line-winner? g h i) 2)
      ((line-winner? a d g) 3)
      ((line-winner? b e h) 4)
      ((line-winner? c f i) 5)
      ((line-winner? a e i) 6)
      ((line-winner? c e g) 7)
      (True -1)))

  (declare local-outcome9 (Mark -> Mark -> Mark
                                -> Mark -> Mark -> Mark
                                -> Mark -> Mark -> Mark
                                -> Outcome))
  (define (local-outcome9 a b c d e f g h i)
    (let winner = (winning-player9 a b c d e f g h i))
    (cond
      ((player-mark? winner) (mark->outcome winner))
      ((all-cells-filled? a b c d e f g h i) DrawOutcome)
      (True OpenOutcome)))

  (declare global-outcome9 (Outcome -> Outcome -> Outcome
                                    -> Outcome -> Outcome -> Outcome
                                    -> Outcome -> Outcome -> Outcome
                                    -> Outcome))
  (define (global-outcome9 a b c d e f g h i)
    (let winner = (winning-player9 (outcome->mark a) (outcome->mark b) (outcome->mark c)
                                   (outcome->mark d) (outcome->mark e) (outcome->mark f)
                                   (outcome->mark g) (outcome->mark h) (outcome->mark i)))
    (cond
      ((player-mark? winner) (mark->outcome winner))
      ((all-boards-closed? a b c d e f g h i) DrawOutcome)
      (True OpenOutcome)))

  (declare local-board-outcome-symbols ((List sym:Symbol) -> sym:Symbol))
  (define (local-board-outcome-symbols cells)
    "Return :X, :O, :DRAW, or NIL for a nine-cell local board."
    (match cells
      ((Cons a (Cons b (Cons c (Cons d (Cons e (Cons f (Cons g (Cons h (Cons i (Nil))))))))))
       (outcome->symbol
        (local-outcome9 (symbol->mark a) (symbol->mark b) (symbol->mark c)
                        (symbol->mark d) (symbol->mark e) (symbol->mark f)
                        (symbol->mark g) (symbol->mark h) (symbol->mark i))))
      (_ open-symbol)))

  (declare global-outcome-symbols ((List sym:Symbol) -> sym:Symbol))
  (define (global-outcome-symbols board-outcomes)
    "Return :X, :O, :DRAW, or NIL for nine local-board outcomes."
    (match board-outcomes
      ((Cons a (Cons b (Cons c (Cons d (Cons e (Cons f (Cons g (Cons h (Cons i (Nil))))))))))
       (outcome->symbol
        (global-outcome9 (symbol->outcome a) (symbol->outcome b) (symbol->outcome c)
                         (symbol->outcome d) (symbol->outcome e) (symbol->outcome f)
                         (symbol->outcome g) (symbol->outcome h) (symbol->outcome i))))
      (_ open-symbol)))

  (declare winning-line-index-symbols ((List sym:Symbol) -> Integer))
  (define (winning-line-index-symbols marks)
    "Return the winning line index, or -1 when no player owns a line."
    (match marks
      ((Cons a (Cons b (Cons c (Cons d (Cons e (Cons f (Cons g (Cons h (Cons i (Nil))))))))))
       (winning-line-index9 (symbol->mark a) (symbol->mark b) (symbol->mark c)
                            (symbol->mark d) (symbol->mark e) (symbol->mark f)
                            (symbol->mark g) (symbol->mark h) (symbol->mark i)))
      (_ -1))))
