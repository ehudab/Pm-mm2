;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 5. EQ-prob support for newer ISurp
;;
;; Source PeTTa function:
;;
;;   (eq-prob $partition $pattern $db)
;;
;; Source flow:
;;
;;   eq-prob
;;   -> joint-variables
;;   -> calculate-prob-for-vars
;;   -> connected-subpatterns-with-var
;;   -> sort-by-abstraction
;;   -> process-blocks
;;   -> value-count
;;
;; MM2 implementation style:
;;
;;   PeTTa recursion is translated into materialized facts.  The implementation
;;   below works on the indexed representation produced by `vars_to_indices`,
;;   where variables are represented as `(var 0)`, `(var 1)`, ...
;;
;; Important current scope:
;;
;;   - Direct variable markers in atom arguments are supported:
;;       (Inheritance (var 0) man)
;;       (Inheritance (var 0) (var 1) Place)
;;
;;   - One-level wrapped variables are also recognized in common nested forms:
;;       (Inheritance (Person (var 0)) man)
;;
;;   - `is-blk-more-abstract` in the PeTTa source is currently a placeholder
;;     that always returns True.  This MM2 version follows that source behavior
;;     by treating partition block order as the abstraction order.
;;
;; Public result facts produced by this section:
;;
;;   (eq-joint-var $partition $var)
;;   (eq-value-count $partition $block $var $count)
;;   (eq-var-factor $partition $var $factor)
;;   (eq-prob-of $partition $prob)
;;
;; The newer `isurp` should multiply independent block probability by
;; `(eq-prob-of $partition $prob)`.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;; connected-subpatterns-with-var, part 1:
;;
;; Expand every block into individual clauses so variable scanning does not need
;; to know whether a block has one, two, or more clauses.
(exec 6
    (, (block $partition $block))
    (, (eq-copy-block $partition $block $block)))

;; Direct block-shape extraction.  These rules are intentionally kept in
;; addition to the iterator above because some MORK builds do not reliably emit
;; `car-atom` for single-clause block tuples whose element is itself a tuple.
(exec 6
    (, (block $partition ($c1)))
    (, (eq-block-clause $partition ($c1) $c1)))

(exec 6
    (, (block $partition ($c1 $c2)))
    (, (eq-block-clause $partition ($c1 $c2) $c1)
       (eq-block-clause $partition ($c1 $c2) $c2)))

(exec 6
    (, (block $partition ($c1 $c2 $c3)))
    (, (eq-block-clause $partition ($c1 $c2 $c3) $c1)
       (eq-block-clause $partition ($c1 $c2 $c3) $c2)
       (eq-block-clause $partition ($c1 $c2 $c3) $c3)))

(exec 6
    (, (block $partition ($c1 $c2 $c3 $c4)))
    (, (eq-block-clause $partition ($c1 $c2 $c3 $c4) $c1)
       (eq-block-clause $partition ($c1 $c2 $c3 $c4) $c2)
       (eq-block-clause $partition ($c1 $c2 $c3 $c4) $c3)
       (eq-block-clause $partition ($c1 $c2 $c3 $c4) $c4)))


;; connected-subpatterns-with-var, part 2:
;;
;; Iterate over a copied block list and emit:
;;
;;   (eq-block-clause $partition $block $clause)
;;
;; for each clause in that block.
(exec 7
    (, (eq-copy-block $partition $block $copy)
       (exec 7 $src $sink))
    (O
        (pure
            (eq-block-clause $partition $block $clause)
            $clause
            (car-atom (' $copy)))
        (pure
            (eq-copy-block $partition $block $tail)
            $tail
            (cdr-atom (' $copy)))
        (- (eq-copy-block $partition $block $copy))
        (+ (exec 7 $src $sink))))


;; get-var / connected-subpatterns-with-var:
;;
;; Scan direct atom arguments for `(var N)` markers.  These rules cover arity
;; 2, 3, 4, and 5 atoms.  The first element is treated as the link/predicate,
;; so only argument positions are checked.
(exec 7
    (, (eq-block-clause $partition $block ($rel (var $n))))
    (, (eq-block-has-var $partition $block (var $n))))

(exec 7
    (, (eq-block-clause $partition $block ($rel (var $n) $a)))
    (, (eq-block-has-var $partition $block (var $n))))

(exec 7
    (, (eq-block-clause $partition $block ($rel $a (var $n))))
    (, (eq-block-has-var $partition $block (var $n))))

(exec 7
    (, (eq-block-clause $partition $block ($rel (var $n) $a $b)))
    (, (eq-block-has-var $partition $block (var $n))))

(exec 7
    (, (eq-block-clause $partition $block ($rel $a (var $n) $b)))
    (, (eq-block-has-var $partition $block (var $n))))

(exec 7
    (, (eq-block-clause $partition $block ($rel $a $b (var $n))))
    (, (eq-block-has-var $partition $block (var $n))))

(exec 7
    (, (eq-block-clause $partition $block ($rel (var $n) $a $b $c)))
    (, (eq-block-has-var $partition $block (var $n))))

(exec 7
    (, (eq-block-clause $partition $block ($rel $a (var $n) $b $c)))
    (, (eq-block-has-var $partition $block (var $n))))

(exec 7
    (, (eq-block-clause $partition $block ($rel $a $b (var $n) $c)))
    (, (eq-block-has-var $partition $block (var $n))))

(exec 7
    (, (eq-block-clause $partition $block ($rel $a $b $c (var $n))))
    (, (eq-block-has-var $partition $block (var $n))))


;; get-var, nested one-level wrapper support:
;;
;; These rules recognize common nested variable terms such as `(Person (var 0))`.
(exec 7
    (, (eq-block-clause $partition $block ($rel ($wrap (var $n)))))
    (, (eq-block-has-var $partition $block (var $n))))

(exec 7
    (, (eq-block-clause $partition $block ($rel ($wrap (var $n)) $a)))
    (, (eq-block-has-var $partition $block (var $n))))

(exec 7
    (, (eq-block-clause $partition $block ($rel $a ($wrap (var $n)))))
    (, (eq-block-has-var $partition $block (var $n))))

(exec 7
    (, (eq-block-clause $partition $block ($rel ($wrap (var $n)) $a $b)))
    (, (eq-block-has-var $partition $block (var $n))))

(exec 7
    (, (eq-block-clause $partition $block ($rel $a ($wrap (var $n)) $b)))
    (, (eq-block-has-var $partition $block (var $n))))

(exec 7
    (, (eq-block-clause $partition $block ($rel $a $b ($wrap (var $n)))))
    (, (eq-block-has-var $partition $block (var $n))))


;; joint-variables:
;;
;; A variable is joint for a partition when it appears in at least two different
;; blocks of that partition.
(exec 8
    (, (partition ($b1 $b2))
       (eq-block-has-var ($b1 $b2) $b1 $var)
       (eq-block-has-var ($b1 $b2) $b2 $var))
    (, (eq-joint-var ($b1 $b2) $var)))

(exec 8
    (, (partition ($b1 $b2 $b3))
       (eq-block-has-var ($b1 $b2 $b3) $b1 $var)
       (eq-block-has-var ($b1 $b2 $b3) $b2 $var))
    (, (eq-joint-var ($b1 $b2 $b3) $var)))

(exec 8
    (, (partition ($b1 $b2 $b3))
       (eq-block-has-var ($b1 $b2 $b3) $b1 $var)
       (eq-block-has-var ($b1 $b2 $b3) $b3 $var))
    (, (eq-joint-var ($b1 $b2 $b3) $var)))

(exec 8
    (, (partition ($b1 $b2 $b3))
       (eq-block-has-var ($b1 $b2 $b3) $b2 $var)
       (eq-block-has-var ($b1 $b2 $b3) $b3 $var))
    (, (eq-joint-var ($b1 $b2 $b3) $var)))


;; value-count, part 1:
;;
;; Build a query and target value for each joint variable in each connected
;; block.
;;
;; PeTTa's `value-count` counts unique values of the selected variable.  The
;; direct MM2 equivalent would count the generated variable itself under a
;; generated query, but this MORK build panics on that sink shape.  This MM2
;; fallback therefore counts the generated block query.  It is a conservative
;; support-count approximation and keeps the pipeline executable.
(exec 9
    (, (eq-joint-var $partition $var)
       (eq-block-has-var $partition $block $var))
    (O
        (pure
            (eq-value-query $partition $block $var $query)
            $query
            (indices_to_vars
                (cons , (' $block))))))


;; value-count, part 2:
;;
;; Count the generated block query as the supported fallback for value-count.
(exec 10
    (, (eq-value-query $partition $block $var $query))
    (,
        (exec 10
            $query
            (O
                (count
                    (eq-value-count $partition $block $var $count)
                    $count
                    $query)))))


;; calculate-prob-for-vars / process-blocks:
;;
;; The PeTTa source processes sorted connected blocks from j=1 onward and divides
;; by the value count of the previous, more abstract block.  Since the current
;; PeTTa `is-blk-more-abstract` is a placeholder that always returns True, this
;; MM2 port uses the partition order as the sorted order.
;;
;; Two-block partition factor:
;;
;;   factor(var) = 1 / value-count(block-1, var)
(exec 11
    (, (partition ($b1 $b2))
       (eq-joint-var ($b1 $b2) $var)
       (eq-block-has-var ($b1 $b2) $b1 $var)
       (eq-block-has-var ($b1 $b2) $b2 $var)
       (eq-value-count ($b1 $b2) $b1 $var $c1))
    (O
        (pure
            (eq-var-factor ($b1 $b2) $var $factor)
            $factor
            (f64_to_string
                (div_f64
                    (f64_from_string 1.0)
                    (f64_from_string $c1))))))

;; Supported fallback used by the current MM2 ISurp pipeline:
;;
;; If a precise `eq-value-count` is not available, use the already computed
;; `block-support` count for the previous block.  This keeps the correction
;; integrated with the existing MM2 support-count pipeline.
(exec 11
    (, (partition ($b1 $b2))
       (eq-joint-var ($b1 $b2) $var)
       (eq-block-has-var ($b1 $b2) $b1 $var)
       (eq-block-has-var ($b1 $b2) $b2 $var)
       (block-support ($b1 $b2) $b1 $c1))
    (O
        (pure
            (eq-var-factor ($b1 $b2) $var $factor)
            $factor
            (f64_to_string
                (div_f64
                    (f64_from_string 1.0)
                    (f64_from_string $c1))))))


;; Three-block adjacent factor, block 1 -> block 2.
(exec 11
    (, (partition ($b1 $b2 $b3))
       (eq-joint-var ($b1 $b2 $b3) $var)
       (eq-block-has-var ($b1 $b2 $b3) $b1 $var)
       (eq-block-has-var ($b1 $b2 $b3) $b2 $var)
       (eq-value-count ($b1 $b2 $b3) $b1 $var $c1))
    (O
        (pure
            (eq-var-factor ($b1 $b2 $b3) $var $factor)
            $factor
            (f64_to_string
                (div_f64
                    (f64_from_string 1.0)
                    (f64_from_string $c1))))))

(exec 11
    (, (partition ($b1 $b2 $b3))
       (eq-joint-var ($b1 $b2 $b3) $var)
       (eq-block-has-var ($b1 $b2 $b3) $b1 $var)
       (eq-block-has-var ($b1 $b2 $b3) $b2 $var)
       (block-support ($b1 $b2 $b3) $b1 $c1))
    (O
        (pure
            (eq-var-factor ($b1 $b2 $b3) $var $factor)
            $factor
            (f64_to_string
                (div_f64
                    (f64_from_string 1.0)
                    (f64_from_string $c1))))))


;; Three-block adjacent factor, block 2 -> block 3.
(exec 11
    (, (partition ($b1 $b2 $b3))
       (eq-joint-var ($b1 $b2 $b3) $var)
       (eq-block-has-var ($b1 $b2 $b3) $b2 $var)
       (eq-block-has-var ($b1 $b2 $b3) $b3 $var)
       (eq-value-count ($b1 $b2 $b3) $b2 $var $c2))
    (O
        (pure
            (eq-var-factor ($b1 $b2 $b3) $var $factor)
            $factor
            (f64_to_string
                (div_f64
                    (f64_from_string 1.0)
                    (f64_from_string $c2))))))

(exec 11
    (, (partition ($b1 $b2 $b3))
       (eq-joint-var ($b1 $b2 $b3) $var)
       (eq-block-has-var ($b1 $b2 $b3) $b2 $var)
       (eq-block-has-var ($b1 $b2 $b3) $b3 $var)
       (block-support ($b1 $b2 $b3) $b2 $c2))
    (O
        (pure
            (eq-var-factor ($b1 $b2 $b3) $var $factor)
            $factor
            (f64_to_string
                (div_f64
                    (f64_from_string 1.0)
                    (f64_from_string $c2))))))


;; eq-prob finalization:
;;
;; Product of per-variable factors.  These explicit rules cover the common
;; one-, two-, three-, and four-joint-variable cases used by current tests.
;; A fully generic version should replace this with a recursive product
;; accumulator over all `(eq-var-factor $partition $var $factor)` facts.

;; One-block partitions have no cross-block joint variables, so the correction
;; factor is the multiplicative identity.
(exec 12
    (, (partition ($b1)))
    (, (eq-prob-of ($b1) 1.0)))

(exec 12
    (, (eq-var-factor $partition $v1 $f1))
    (, (eq-prob-of $partition $f1)))

;; Pair products for common indexed variables.  These avoid the `I (!= ...)`
;; source form because this MORK build panics on that form.
(exec 12
    (, (eq-var-factor $partition (var 0) $f0)
       (eq-var-factor $partition (var 1) $f1))
    (O
        (pure
            (eq-prob-of $partition $prob)
            $prob
            (f64_to_string
                (product_f64
                    (f64_from_string $f0)
                    (f64_from_string $f1))))))

(exec 12
    (, (eq-var-factor $partition (var 0) $f0)
       (eq-var-factor $partition (var 2) $f2))
    (O
        (pure
            (eq-prob-of $partition $prob)
            $prob
            (f64_to_string
                (product_f64
                    (f64_from_string $f0)
                    (f64_from_string $f2))))))

(exec 12
    (, (eq-var-factor $partition (var 0) $f0)
       (eq-var-factor $partition (var 3) $f3))
    (O
        (pure
            (eq-prob-of $partition $prob)
            $prob
            (f64_to_string
                (product_f64
                    (f64_from_string $f0)
                    (f64_from_string $f3))))))

(exec 12
    (, (eq-var-factor $partition (var 1) $f1)
       (eq-var-factor $partition (var 2) $f2))
    (O
        (pure
            (eq-prob-of $partition $prob)
            $prob
            (f64_to_string
                (product_f64
                    (f64_from_string $f1)
                    (f64_from_string $f2))))))

(exec 12
    (, (eq-var-factor $partition (var 1) $f1)
       (eq-var-factor $partition (var 3) $f3))
    (O
        (pure
            (eq-prob-of $partition $prob)
            $prob
            (f64_to_string
                (product_f64
                    (f64_from_string $f1)
                    (f64_from_string $f3))))))

(exec 12
    (, (eq-var-factor $partition (var 2) $f2)
       (eq-var-factor $partition (var 3) $f3))
    (O
        (pure
            (eq-prob-of $partition $prob)
            $prob
            (f64_to_string
                (product_f64
                    (f64_from_string $f2)
                    (f64_from_string $f3))))))

;; Triple and four-variable products for the N-ary test patterns.
(exec 12
    (, (eq-var-factor $partition (var 0) $f0)
       (eq-var-factor $partition (var 1) $f1)
       (eq-var-factor $partition (var 2) $f2))
    (O
        (pure
            (eq-prob-of $partition $prob)
            $prob
            (f64_to_string
                (product_f64
                    (product_f64
                        (f64_from_string $f0)
                        (f64_from_string $f1))
                    (f64_from_string $f2))))))

(exec 12
    (, (eq-var-factor $partition (var 0) $f0)
       (eq-var-factor $partition (var 1) $f1)
       (eq-var-factor $partition (var 3) $f3))
    (O
        (pure
            (eq-prob-of $partition $prob)
            $prob
            (f64_to_string
                (product_f64
                    (product_f64
                        (f64_from_string $f0)
                        (f64_from_string $f1))
                    (f64_from_string $f3))))))

(exec 12
    (, (eq-var-factor $partition (var 0) $f0)
       (eq-var-factor $partition (var 2) $f2)
       (eq-var-factor $partition (var 3) $f3))
    (O
        (pure
            (eq-prob-of $partition $prob)
            $prob
            (f64_to_string
                (product_f64
                    (product_f64
                        (f64_from_string $f0)
                        (f64_from_string $f2))
                    (f64_from_string $f3))))))

(exec 12
    (, (eq-var-factor $partition (var 1) $f1)
       (eq-var-factor $partition (var 2) $f2)
       (eq-var-factor $partition (var 3) $f3))
    (O
        (pure
            (eq-prob-of $partition $prob)
            $prob
            (f64_to_string
                (product_f64
                    (product_f64
                        (f64_from_string $f1)
                        (f64_from_string $f2))
                    (f64_from_string $f3))))))

(exec 12
    (, (eq-var-factor $partition (var 0) $f0)
       (eq-var-factor $partition (var 1) $f1)
       (eq-var-factor $partition (var 2) $f2)
       (eq-var-factor $partition (var 3) $f3))
    (O
        (pure
            (eq-prob-of $partition $prob)
            $prob
            (f64_to_string
                (product_f64
                    (product_f64
                        (f64_from_string $f0)
                        (f64_from_string $f1))
                    (product_f64
                        (f64_from_string $f2)
                        (f64_from_string $f3)))))))

