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
;;   - Direct variable markers in binary predicate atom arguments are supported:
;;       (Inheritance (var 0) man)
;;       (Inheritance man (var 0))
;;       (Inheritance (var 0) (var 1))
;;
;;   - Abstractness ordering is delegated to `03_abstractness_sort.metta`.
;;     That module materializes the most abstract block connected to each joint
;;     variable and exposes its support.
;;
;; Public result facts produced by this section:
;;
;;   (eq-joint-var $partition $var)
;;   (eq-value-count $partition $block $var $count)
;;   (abstractness-sort-request $partition $var)
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
(exec (jsd 121 eq-copy-block)
    (, (block $partition $block))
    (, (eq-copy-block $partition $block $block)))

;; Direct block-shape extraction.  These rules are intentionally kept in
;; addition to the iterator above because some MORK builds do not reliably emit
;; `car-atom` for single-clause block tuples whose element is itself a tuple.
(exec (jsd 122 eq-block-clause-1)
    (, (block $partition ($c1)))
    (, (eq-block-clause $partition ($c1) $c1)))

(exec (jsd 123 eq-block-clause-2)
    (, (block $partition ($c1 $c2)))
    (, (eq-block-clause $partition ($c1 $c2) $c1)
       (eq-block-clause $partition ($c1 $c2) $c2)))

(exec (jsd 123 eq-block-clause-3)
    (, (block $partition ($c1 $c2 $c3)))
    (, (eq-block-clause $partition ($c1 $c2 $c3) $c1)
       (eq-block-clause $partition ($c1 $c2 $c3) $c2)
       (eq-block-clause $partition ($c1 $c2 $c3) $c3)))

(exec (jsd 123 eq-block-clause-4)
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
(exec (jsd 124 eq-block-iterator)
    (, (eq-copy-block $partition $block $copy)
       (exec (jsd 124 eq-block-iterator) $src $sink))
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
        (+ (exec (jsd 124 eq-block-iterator) $src $sink))))


;; get-var / connected-subpatterns-with-var:
;;
;; Scan direct arguments for `(var N)` markers in binary predicate atoms only:
;;
;;   ($rel $left $right)
;;
;; The first element is treated as the link/predicate, so only the two argument
;; positions are checked.  This intentionally excludes n-ary predicate atoms
;; such as `($rel $x $a $b)` and nested wrapper terms.
(exec (jsd 125 eq-scan-left-var)
    (, (eq-block-clause $partition $block ($rel (var $n) $a)))
    (, (eq-block-has-var $partition $block (var $n))))

(exec (jsd 125 eq-scan-right-var)
    (, (eq-block-clause $partition $block ($rel $a (var $n))))
    (, (eq-block-has-var $partition $block (var $n))))


;; joint-variables:
;;
;; A variable is joint for a partition when it appears in at least two different
;; blocks of that partition.
(exec (jsd 126 eq-joint-var-2)
    (, (partition $pattern ($b1 $b2))
       (eq-block-has-var ($b1 $b2) $b1 $var)
       (eq-block-has-var ($b1 $b2) $b2 $var))
    (, (eq-joint-var ($b1 $b2) $var)))

(exec (jsd 126 eq-joint-var-3-12)
    (, (partition $pattern ($b1 $b2 $b3))
       (eq-block-has-var ($b1 $b2 $b3) $b1 $var)
       (eq-block-has-var ($b1 $b2 $b3) $b2 $var))
    (, (eq-joint-var ($b1 $b2 $b3) $var)))

(exec (jsd 126 eq-joint-var-3-13)
    (, (partition $pattern ($b1 $b2 $b3))
       (eq-block-has-var ($b1 $b2 $b3) $b1 $var)
       (eq-block-has-var ($b1 $b2 $b3) $b3 $var))
    (, (eq-joint-var ($b1 $b2 $b3) $var)))

(exec (jsd 126 eq-joint-var-3-23)
    (, (partition $pattern ($b1 $b2 $b3))
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


;; value-count, part 2:
;;
;; Count the generated block query as the supported fallback for value-count.


(exec (jsd 128 eq-value-count)
    (, (eq-joint-var $partition $var) (eq-block-has-var $partition $block $var) (sup-num-query $block $db $q) (INPUT DB $db))
    (O
        (pure
            (exec (jsd 128 eq-value-count)
                $query
                (O
                    (count 
                        (eq-value-count $block $db $sup)
                        $sup
                        ($query)
                    )
                )
            )
            $query
            (indices_to_vars (cons , (' $q)))
        )
    )
)




;; calculate-prob-for-vars / process-blocks:
;;
;; The PeTTa source sorts connected blocks by abstractness, then divides by the
;; value count/support of the previous more abstract block.  In this MM2 port,
;; `03_abstractness_sort.metta` performs the abstractness choice and writes:
;;
;;   (most-abstract-block-support $partition $var $block $count)
;;
;; This rule turns that count into the per-variable equality correction:
;;
;;   factor(var) = 1 / support(most abstract connected block)
(exec (jsd 129 eq-abstractness-request)
    (, (eq-joint-var $partition $var))
    (, (abstractness-sort-request $partition $var)))



;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Abstractness sorting for blocks of binary predicate clauses
;;
;; Scope:
;;
;;   This module assumes each clause is a binary relation triple:
;;
;;     ($rel $left $right)
;;
;;   Blocks and partitions may still contain many clauses/blocks:
;;
;;     block     = (($rel $left $right) ...)
;;     partition = (block ...)
;;
;; Purpose:
;;
;;   `eq-prob` needs the most abstract block connected to a joint variable.  The
;;   C++/PeTTa implementation ranks blocks by syntactic abstractness relative to
;;   that joint variable, then uses value-count/support from the selected block.
;;
;; MM2 approximation:
;;
;;   The full C++ relation uses unification over block partitions and subsets.
;;   This MM2 version keeps the same intent for binary triplet clauses by using
;;   a deterministic weighted score:
;;
;;     1. syntactic triplet abstractness relative to the joint variable
;;        - a non-joint variable argument is more abstract than a constant
;;     2. fewer clauses is more abstract
;;     3. larger support is the empirical fallback
;;     4. equal scores keep original partition order
;;
;; Public request:
;;
;;   (abstractness-sort-request $partition $var)
;;
;; Public result facts:
;;
;;   (abstract-block-clause $partition $block $clause)
;;   (abstract-open-score $partition $var $block $clause $score)
;;   (abstract-size-priority $partition $block $priority)
;;   (abstract-block-score $partition $var $block $score)
;;   (most-abstract-block $partition $var $block)
;;   (most-abstract-block-support $partition $var $block $support)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;; Expand block tuples into clauses.  This duplicates a small part of
;; `04_eq_prob.metta` so the sorter can be tested independently.
(exec (jsd 131 abstract-expand-1)
    (, (abstractness-sort-request $partition $var)
       (block $partition ($c1)))
    (, (abstract-block-clause $partition ($c1) $c1)
       (abstract-size-priority $partition ($c1) 4000000000000)))

(exec (jsd 131 abstract-expand-2)
    (, (abstractness-sort-request $partition $var)
       (block $partition ($c1 $c2)))
    (, (abstract-block-clause $partition ($c1 $c2) $c1)
       (abstract-block-clause $partition ($c1 $c2) $c2)
       (abstract-size-priority $partition ($c1 $c2) 3000000000000)))

(exec (jsd 131 abstract-expand-3)
    (, (abstractness-sort-request $partition $var)
       (block $partition ($c1 $c2 $c3)))
    (, (abstract-block-clause $partition ($c1 $c2 $c3) $c1)
       (abstract-block-clause $partition ($c1 $c2 $c3) $c2)
       (abstract-block-clause $partition ($c1 $c2 $c3) $c3)
       (abstract-size-priority $partition ($c1 $c2 $c3) 2000000000000)))

(exec (jsd 131 abstract-expand-4)
    (, (abstractness-sort-request $partition $var)
       (block $partition ($c1 $c2 $c3 $c4)))
    (, (abstract-block-clause $partition ($c1 $c2 $c3 $c4) $c1)
       (abstract-block-clause $partition ($c1 $c2 $c3 $c4) $c2)
       (abstract-block-clause $partition ($c1 $c2 $c3 $c4) $c3)
       (abstract-block-clause $partition ($c1 $c2 $c3 $c4) $c4)
       (abstract-size-priority $partition ($c1 $c2 $c3 $c4) 1000000000000)))


;; Clause-level syntactic abstractness relative to the requested joint variable.
;;
;; If the joint variable is in one argument position, the other argument is the
;; one that determines whether this clause is more open/abstract:
;;
;;   ($rel (var N) (var M)) -> 1
;;   ($rel (var N) const)   -> 0
;;   ($rel (var M) (var N)) -> 1
;;   ($rel const   (var N)) -> 0
;;
;; `is_var` lets the same rule cover constants and indexed variables without
;; needing negation.
(exec (jsd 132 abstract-open-right)
    (, (abstractness-sort-request $partition (var $n))
       (abstract-block-clause $partition $block ($rel (var $n) $right)))
    (O
        (pure
            (abstract-open-score $partition (var $n) $block ($rel (var $n) $right) $score)
            $score
            (i8_to_string (is_var (' $right))))))

(exec (jsd 133 abstract-open-left)
    (, (abstractness-sort-request $partition (var $n))
       (abstract-block-clause $partition $block ($rel $left (var $n))))
    (O
        (pure
            (abstract-open-score $partition (var $n) $block ($rel $left (var $n)) $score)
            $score
            (i8_to_string (is_var (' $left))))))

;; Open-score totals for one-, two-, three-, and four-clause blocks.  Totals are
;; based on clauses connected to the joint variable; unrelated concrete clauses
;; are handled by the block-size fallback.
(exec (jsd 134 abstract-total-1)
    (, (abstract-open-score $partition $var ($c1) $c1 $s1))
    (, (abstract-open-total $partition $var ($c1) $s1)))

(exec (jsd 134 abstract-total-2-c1)
    (, (abstract-open-score $partition $var ($c1 $c2) $c1 $s1))
    (, (abstract-open-total $partition $var ($c1 $c2) $s1)))

(exec (jsd 134 abstract-total-2-c2)
    (, (abstract-open-score $partition $var ($c1 $c2) $c2 $s2))
    (, (abstract-open-total $partition $var ($c1 $c2) $s2)))

(exec (jsd 134 abstract-total-2)
    (, (abstract-open-score $partition $var ($c1 $c2) $c1 $s1)
       (abstract-open-score $partition $var ($c1 $c2) $c2 $s2))
    (O
        (pure
            (abstract-open-total $partition $var ($c1 $c2) $score)
            $score
            (i64_to_string
                (sum_i64
                    (i64_from_string $s1)
                    (i64_from_string $s2))))))

(exec (jsd 134 abstract-total-3-c1)
    (, (abstract-open-score $partition $var ($c1 $c2 $c3) $c1 $s1))
    (, (abstract-open-total $partition $var ($c1 $c2 $c3) $s1)))

(exec (jsd 134 abstract-total-3-c2)
    (, (abstract-open-score $partition $var ($c1 $c2 $c3) $c2 $s2))
    (, (abstract-open-total $partition $var ($c1 $c2 $c3) $s2)))

(exec (jsd 134 abstract-total-3-c3)
    (, (abstract-open-score $partition $var ($c1 $c2 $c3) $c3 $s3))
    (, (abstract-open-total $partition $var ($c1 $c2 $c3) $s3)))

(exec (jsd 134 abstract-total-3)
    (, (abstract-open-score $partition $var ($c1 $c2 $c3) $c1 $s1)
       (abstract-open-score $partition $var ($c1 $c2 $c3) $c2 $s2)
       (abstract-open-score $partition $var ($c1 $c2 $c3) $c3 $s3))
    (O
        (pure
            (abstract-open-total $partition $var ($c1 $c2 $c3) $score)
            $score
            (i64_to_string
                (sum_i64
                    (i64_from_string $s1)
                    (i64_from_string $s2)
                    (i64_from_string $s3))))))

(exec (jsd 134 abstract-total-4-c1)
    (, (abstract-open-score $partition $var ($c1 $c2 $c3 $c4) $c1 $s1))
    (, (abstract-open-total $partition $var ($c1 $c2 $c3 $c4) $s1)))

(exec (jsd 134 abstract-total-4-c2)
    (, (abstract-open-score $partition $var ($c1 $c2 $c3 $c4) $c2 $s2))
    (, (abstract-open-total $partition $var ($c1 $c2 $c3 $c4) $s2)))

(exec (jsd 134 abstract-total-4-c3)
    (, (abstract-open-score $partition $var ($c1 $c2 $c3 $c4) $c3 $s3))
    (, (abstract-open-total $partition $var ($c1 $c2 $c3 $c4) $s3)))

(exec (jsd 134 abstract-total-4-c4)
    (, (abstract-open-score $partition $var ($c1 $c2 $c3 $c4) $c4 $s4))
    (, (abstract-open-total $partition $var ($c1 $c2 $c3 $c4) $s4)))

(exec (jsd 134 abstract-total-4)
    (, (abstract-open-score $partition $var ($c1 $c2 $c3 $c4) $c1 $s1)
       (abstract-open-score $partition $var ($c1 $c2 $c3 $c4) $c2 $s2)
       (abstract-open-score $partition $var ($c1 $c2 $c3 $c4) $c3 $s3)
       (abstract-open-score $partition $var ($c1 $c2 $c3 $c4) $c4 $s4))
    (O
        (pure
            (abstract-open-total $partition $var ($c1 $c2 $c3 $c4) $score)
            $score
            (i64_to_string
                (sum_i64
                    (i64_from_string $s1)
                    (i64_from_string $s2)
                    (i64_from_string $s3)
                    (i64_from_string $s4))))))


;; Weighted block score.
;;
;; The weights encode the priority order:
;;
;;   open-total * 1000000000000000  >  size-priority  >  support
;;
;; Support is intentionally last.  It breaks ties empirically, but it does not
;; override syntactic openness or the fewer-clauses fallback.
(exec (jsd 135 abstract-block-score)
    (, (abstract-open-total $partition $var $block $open-total)
       (abstract-size-priority $partition $block $size-priority)
       (support-of $block $db $support) (block $partition $indexed-block))
    (O
        (pure
            (abstract-block-score $partition $var $block $score)
            $score
            (i64_to_string
                (sum_i64
                    (product_i64
                        (i64_from_string $open-total)
                        (i64_from_string 1000000000000000))
                    (i64_from_string $size-priority)
                    (i64_from_string $support))))))


;; Pairwise comparisons between block scores.
(exec (jsd 136 abstract-score-compare)
    (, (abstract-block-score $partition $var $left $left-score)
       (abstract-block-score $partition $var $right $right-score))
    (O
        (pure
            (abstract-score-ge? $partition $var $left $right $ge)
            $ge
            (ge_i64
                (i64_from_string $left-score)
                (i64_from_string $right-score)))
        (pure
            (abstract-score-gt? $partition $var $left $right $gt)
            $gt
            (gt_i64
                (i64_from_string $left-score)
                (i64_from_string $right-score)))))


;; Select the highest-scoring block.  Ties keep partition order.
(exec (jsd 137 most-abstract-1)
    (, (partition $pattern ($b1))
       (abstractness-sort-request ($b1) $var)
       (abstract-block-score ($b1) $var $b1 $s1))
    (, (most-abstract-block ($b1) $var $b1)))

(exec (jsd 137 most-abstract-2-left)
    (, (partition $pattern ($b1 $b2))
       (abstractness-sort-request ($b1 $b2) $var)
       (abstract-score-ge? ($b1 $b2) $var $b1 $b2 true))
    (, (most-abstract-block ($b1 $b2) $var $b1)))

(exec (jsd 137 most-abstract-2-right)
    (, (partition $pattern ($b1 $b2))
       (abstractness-sort-request ($b1 $b2) $var)
       (abstract-score-gt? ($b1 $b2) $var $b2 $b1 true))
    (, (most-abstract-block ($b1 $b2) $var $b2)))

(exec (jsd 137 most-abstract-3-first)
    (, (partition $pattern ($b1 $b2 $b3))
       (abstractness-sort-request ($b1 $b2 $b3) $var)
       (abstract-score-ge? ($b1 $b2 $b3) $var $b1 $b2 true)
       (abstract-score-ge? ($b1 $b2 $b3) $var $b1 $b3 true))
    (, (most-abstract-block ($b1 $b2 $b3) $var $b1)))

(exec (jsd 137 most-abstract-3-second)
    (, (partition $pattern ($b1 $b2 $b3))
       (abstractness-sort-request ($b1 $b2 $b3) $var)
       (abstract-score-gt? ($b1 $b2 $b3) $var $b2 $b1 true)
       (abstract-score-ge? ($b1 $b2 $b3) $var $b2 $b3 true))
    (, (most-abstract-block ($b1 $b2 $b3) $var $b2)))

(exec (jsd 137 most-abstract-3-third)
    (, (partition $pattern ($b1 $b2 $b3))
       (abstractness-sort-request ($b1 $b2 $b3) $var)
       (abstract-score-gt? ($b1 $b2 $b3) $var $b3 $b1 true)
       (abstract-score-gt? ($b1 $b2 $b3) $var $b3 $b2 true))
    (, (most-abstract-block ($b1 $b2 $b3) $var $b3)))


;; Expose the support of the chosen block, which is the value eq-prob needs
;; next as its divisor/count input.
(exec (jsd 138 most-abstract-support)
    (, (most-abstract-block $partition $var $block)
       (support-of $block $db $support) (block $partition $indexed-block))
    (, (most-abstract-block-support $partition $var $block $support)))



(exec (jsd 140 eq-var-factor)
    (, (eq-joint-var $partition $var)
       (most-abstract-block-support $partition $var $most-abstract-block $count))
    (O
        (pure
            (eq-var-factor $partition $var $factor)
            $factor
            (f64_to_string
                (div_f64
                    (f64_from_string 1.0)
                    (f64_from_string $count))))))


;; eq-prob finalization:
;;
;; Product of per-variable factors.  These explicit rules cover the common
;; one-, two-, three-, and four-joint-variable cases used by current tests.
;; A fully generic version should replace this with a recursive product
;; accumulator over all `(eq-var-factor $partition $var $factor)` facts.

;; One-block partitions have no cross-block joint variables, so the correction
;; factor is the multiplicative identity.
(exec (jsd 141 eq-prob-identity)
    (, (partition $pattern ($b1)))
    (, (eq-prob-of ($b1) 1.0)))

(exec (jsd 141 eq-prob-single)
    (, (eq-var-factor $partition $v1 $f1))
    (, (eq-prob-of $partition $f1)))


(exec (jsd 141 eq-prob-var-01)
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

(exec (jsd 131 eq-prob-var-02)
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

(exec (jsd 141 eq-prob-var-03)
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

(exec (jsd 141 eq-prob-var-12)
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

(exec (jsd 141 eq-prob-var-13)
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

(exec (jsd 141 eq-prob-var-23)
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

;; Triple and four-variable products for partitions that expose multiple joint
;; variables across binary predicate clauses.
(exec (jsd 141 eq-prob-var-012)
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

(exec (jsd 141 eq-prob-var-013)
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

(exec (jsd 141 eq-prob-var-023)
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

(exec (jsd 141 eq-prob-var-123)
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

(exec (jsd 141 eq-prob-var-0123)
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
