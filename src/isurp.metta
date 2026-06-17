;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ISurp in MM2
;;
;; This file is a single-file MM2 implementation of the current `isurp-old`
;; pipeline from:
;;
;;   ../../hyperon-miner/experiments/surprisingness/isurp-old.metta
;;
;; The implementation is written as staged MM2 `exec` transactions.  A MeTTa
;; function call such as `(isurp-old pattern db normalize)` becomes a dataflow
;; pipeline:
;;
;;   input pattern/support
;;   -> total count
;;   -> empirical pattern probability
;;   -> partitions of the conjuncts
;;   -> block probabilities
;;   -> partition probability products
;;   -> expected interval [emin, emax]
;;   -> distance from interval
;;   -> optional normalization
;;
;; Required grounded helpers:
;;
;;   From MM2-Helper:
;;     partitions, vars_to_indices, indices_to_vars, factorial,
;;     falling_factorial
;;
;;   From mm2-stdlib / MORK pure helpers:
;;     size-atom, car-atom, cdr-atom, min-atom, max-atom,
;;     bool and numeric conversions/operators
;;
;; Input contract:
;;
;;   A caller must provide:
;;
;;     (INPUT DB db)
;;     (INPUT DB-SIZE <number-of-db-atoms>)
;;     (INPUT NORMALIZATION TRUE)    ; or FALSE
;;     (INPUT PATTERN (<comma-pattern> <support>))
;;
;;   Example:
;;
;;     (INPUT DB db)
;;     (INPUT DB-SIZE 60)
;;     (INPUT NORMALIZATION TRUE)
;;     (INPUT PATTERN ((, (Inheritance $x man)
;;                        (Inheritance $x ugly)
;;                        (Inheritance $x sodaDrinker)) 5))
;;
;; Output:
;;
;;     (isurp-of $pattern $value)
;;
;; Important:
;;
;;   Running this file by itself is only a syntax/load check.  Because this file
;;   intentionally contains no `(INPUT ...)` facts or DB atoms, `mork run
;;   src/isurp.metta` will finish with only the reusable function definitions in
;;   the result space.
;;
;; Compatibility note:
;;
;;   This file intentionally keeps the currently validated algorithm from
;;   `src/surp.metta`, but gives the output a cleaner name: `isurp-of`.
;;   The product/range stage is still explicit for 3-conjunct old-isurp
;;   patterns, which is the currently validated case.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 1. Reusable function definitions
;;
;; MM2 does not call these definitions directly.  Each definition is stored as
;; data with the shape:
;;
;;   ((name args -> output-predicate) source-pattern sink-template)
;;
;; Later stages match the definition and spawn a real `(exec ... source sink)`.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;; count-db
;;
;; Source MeTTa idea:
;;   db_size($db)
;;
;; MM2 implementation:
;;   Count all facts predicated by the chosen DB name, for example `(db fact)`.
;;
;; In the current public input contract, `INPUT DB-SIZE` is authoritative because
;; temporary MM2 facts can otherwise pollute automatic DB-size counting.  This
;; definition is still kept here because it documents and supports a future
;; fully data-driven DB-size path.
((count-db $db-name -> $out)
    (, ($db-name $fact))
    (O
        (count ($out $db-name $count) $count $fact)))


;; count-conjuncts
;;
;; Source MeTTa equivalent:
;;   (n_conjuncts_new $pattern)
;;
;; A conjunctive pattern has the shape:
;;
;;   (, clause-1 clause-2 clause-3)
;;
;; `(cdr-atom pattern)` removes the leading comma and leaves the clause list.
;; `size-atom` then counts that list.
((count-conjuncts $pattern -> $out)
    (, (INPUT PATTERN ($pattern $support)))
    (O
        (pure
            ($out $pattern $count)
            $count
            (size-atom
                (cdr-atom (' $pattern))))))


;; total-counts
;;
;; Source MeTTa equivalent:
;;
;;   (total_counts $pattern $db)
;;   = C(db_size, n_conjuncts)
;;
;; The source implementation uses binomial count, not db_size^n.
;;
;; Formula:
;;
;;   C(n, k) = falling_factorial(n, k) / factorial(k)
;;
;; Result fact:
;;
;;   (total-count-of $pattern $total)
((total-counts $db $pattern -> $out)
    (, (INPUT DB-SIZE $n)
       (num-of-conjuncts $pattern $k))
    (O
        (pure
            ($out $pattern $total)
            $total
            (i64_to_string
                (div_i64
                    (falling_factorial
                        (i64_from_string $n)
                        (i64_from_string $k))
                    (factorial
                        (i64_from_string $k)))))))


;; prob
;;
;; Source MeTTa equivalent:
;;
;;   (prob $pattern $db $total_count)
;;   = sup-num($db, $pattern) / total_count
;;
;; In this MM2 file the full-pattern support is provided by:
;;
;;   (INPUT PATTERN ($pattern $support))
;;
;; This keeps the top-level pattern support explicit and makes validation easier.
((prob $pattern $db -> $out)
    (, (INPUT PATTERN ($pattern $support))
       (total-count-of $pattern $count))
    (O
        (pure
            ($out $pattern $prob)
            $prob
            (f64_to_string
                (div_f64
                    (f64_from_string $support)
                    (f64_from_string $count))))))


;; dst-from-interval
;;
;; Source MeTTa equivalent:
;;
;;   (dst_from_interval $emin $emax $emp)
;;
;; Cases:
;;
;;   emp > emax            -> emp - emax
;;   emp < emin            -> emin - emp
;;   emin <= emp <= emax   -> 0.0
;;
;; MM2 materializes the three booleans as facts, then later execs select the
;; successful case.
((dst-from-interval $pattern $emin $emax $emp -> $out)
    (, (dst-request $pattern $emin $emax $emp $out))
    (O
        (pure
            (dst-above? $pattern $emin $emax $emp $out $above)
            $above
            (gt_f64
                (f64_from_string $emp)
                (f64_from_string $emax)))
        (pure
            (dst-below? $pattern $emin $emax $emp $out $below)
            $below
            (lt_f64
                (f64_from_string $emp)
                (f64_from_string $emin)))
        (pure
            (dst-inside? $pattern $emin $emax $emp $out $inside)
            $inside
            (and_bool
                (le_f64
                    (f64_from_string $emin)
                    (f64_from_string $emp))
                (le_f64
                    (f64_from_string $emp)
                    (f64_from_string $emax))))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 2. Pipeline bootstrap
;;
;; This stage finds the function definitions above and creates the first real
;; execs.  It also normalizes variables in the pattern:
;;
;;   $x, $y, ... -> (var 0), (var 1), ...
;;
;; That is necessary because generated partitions must preserve variable
;; identity across blocks.  Later, `indices_to_vars` converts the markers back
;; into real MM2 variables for support-count queries.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(exec 1
    (, (INPUT DB $db-name)
       (INPUT PATTERN ($pattern $support))
       ((count-db $db-name -> db-size) $src-of-count $sink-of-count)
       ((count-conjuncts $pattern -> num-of-conjuncts) $src-of-cnj $sink-of-cnj)
       ((total-counts $db-name $pattern -> total-count-of) $src-of-tc $sink-of-tc)
       ((prob $pattern $db-name -> prob-of) $src-of-prob $sink-of-prob))
    (O
        ;; Optional DB-size count path.  The current `total-counts` definition
        ;; uses `INPUT DB-SIZE`, but this fact can help with debugging.
        (+ (exec 0 $src-of-count $sink-of-count))

        ;; Count clauses in the input comma pattern.
        (+ (exec 0 $src-of-cnj $sink-of-cnj))

        ;; Compute C(db_size, number_of_conjuncts).
        (+ (exec 1 $src-of-tc $sink-of-tc))

        ;; Compute empirical pattern probability from the provided support.
        (+ (exec 2 $src-of-prob $sink-of-prob))

        ;; Convert pattern variables into stable index markers before
        ;; partition generation.
        (pure
            (indexed-pattern $indexed-copy)
            $indexed-copy
            (vars_to_indices
                (cdr-atom (' $pattern))))
        (pure
            (indexed-pattern-of $pattern $indexed-copy)
            $indexed-copy
                (vars_to_indices
                    (cdr-atom (' $pattern))))))


;; Newer ISurp needs only the indexed pattern and should not depend on the
;; older all-in-one bootstrap rule above.  Keeping this separate makes the
;; upward path into `do-ji-prob` reliable even when old support facts are not
;; requested.
(exec 1
    (, (INPUT PATTERN ($pattern $support)))
    (O
        (pure
            (indexed-pattern $indexed-copy)
            $indexed-copy
            (vars_to_indices
                (cdr-atom (' $pattern))))
        (pure
            (indexed-pattern-of $pattern $indexed-copy)
            $indexed-copy
            (vars_to_indices
                (cdr-atom (' $pattern))))))


;; Fallback for callers that already provide indexed variables.
(exec 1
    (, (INPUT PATTERN ((, $c1) $support)))
    (, (indexed-pattern ($c1))
       (indexed-pattern-of (, $c1) ($c1))))

(exec 1
    (, (INPUT PATTERN ((, $c1 $c2) $support)))
    (, (indexed-pattern ($c1 $c2))
       (indexed-pattern-of (, $c1 $c2) ($c1 $c2))))

(exec 1
    (, (INPUT PATTERN ((, $c1 $c2 $c3) $support)))
    (, (indexed-pattern ($c1 $c2 $c3))
       (indexed-pattern-of (, $c1 $c2 $c3) ($c1 $c2 $c3))))


;; Explicit fallback partitions for indexed inputs.  These follow
;; `partitions-wout-pattern`: the original full pattern is excluded.
(exec 2
    (, (indexed-pattern ($c1 $c2)))
    (,
        (ji-prob-partitions-of ($c1 $c2) ((($c1) ($c2))))
        (do-ji-prob-request ((($c1) ($c2))))
        (partition (($c1) ($c2)))
        (block (($c1) ($c2)) ($c1))
        (block (($c1) ($c2)) ($c2))))


(exec 2
    (, (indexed-pattern ($c1 $c2 $c3)))
    (,
        (ji-prob-partitions-of ($c1 $c2 $c3)
            ((($c1) ($c2 $c3))
             (($c1 $c3) ($c2))
             (($c1 $c2) ($c3))
             (($c1) ($c2) ($c3))))
        (do-ji-prob-request
            ((($c1) ($c2 $c3))
             (($c1 $c3) ($c2))
             (($c1 $c2) ($c3))
             (($c1) ($c2) ($c3))))
        (partition (($c1) ($c2 $c3)))
        (partition (($c1 $c3) ($c2)))
        (partition (($c1 $c2) ($c3)))
        (partition (($c1) ($c2) ($c3)))
        (block (($c1) ($c2 $c3)) ($c1))
        (block (($c1) ($c2 $c3)) ($c2 $c3))
        (block (($c1 $c3) ($c2)) ($c1 $c3))
        (block (($c1 $c3) ($c2)) ($c2))
        (block (($c1 $c2) ($c3)) ($c1 $c2))
        (block (($c1 $c2) ($c3)) ($c3))
        (block (($c1) ($c2) ($c3)) ($c1))
        (block (($c1) ($c2) ($c3)) ($c2))
        (block (($c1) ($c2) ($c3)) ($c3))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 3. Generate partitions
;;
;; Source MeTTa equivalent:
;;
;;   (partitions-wout-pattern (cdr-atom $pattern))
;;
;; Current helper:
;;
;;   (partitions indexed-conjunct-list)
;;
;; The helper returns a list of partitions.  Each partition is a list of blocks,
;; and each block is a list of conjuncts.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(exec 2
    (, (indexed-pattern $indexed-pattern))
    (O
        (pure
            (partitions-of $indexed-pattern $indexed-partition)
            $indexed-partition
            (partitions (' $indexed-pattern)))
        (pure
            (ji-prob-partitions-of $indexed-pattern $indexed-partition)
            $indexed-partition
            (partitions (' $indexed-pattern)))
        (pure
            (do-ji-prob-request $indexed-partition)
            $indexed-partition
            (partitions (' $indexed-pattern)))))


;; Iterate through the partition list.
;;
;; This loop repeatedly:
;;
;;   1. takes the first partition with `car-atom`
;;   2. writes `(partition $car)`
;;   3. replaces the remaining list with `cdr-atom`
;;   4. writes itself back
;;
;; It halts naturally when the remaining list no longer has a first element.
(exec 3
    (, (partitions-of $indexed-pattern $indexed-partition)
       (exec 3 $src $sink))
    (O
        (pure
            (partition $car)
            $car
            (car-atom (' $indexed-partition)))
        (pure
            (partitions-of $indexed-pattern $cdr)
            $cdr
            (cdr-atom (' $indexed-partition)))
        (- (partitions-of $indexed-pattern $indexed-partition))
        (+ (exec 3 $src $sink))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 4. Expand partitions into blocks
;;
;; Source MeTTa equivalent:
;;
;;   isurp-old_ loops through partitions
;;   iprob loops through blocks inside one partition
;;
;; MM2 materializes:
;;
;;   (partition $partition)
;;   (block $partition $block)
;;
;; Keeping `$partition` on every `block` fact is important because later stages
;; must know which block probabilities should be multiplied together.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Copy the partition so the block iterator can consume the copy without losing
;; the original partition shape.
(exec 4
    (, (partition $partition))
    (, (copy-of-partition $partition $partition)))


;; Iterate through the copied partition and write one `(block partition block)`
;; fact per block.
(exec 5
    (, (copy-of-partition $partition $partition-copy)
       (exec 5 $src $sink))
    (O
        (pure
            (block $partition $block)
            $block
            (car-atom (' $partition-copy)))
        (pure
            (copy-of-partition $partition $cdr)
            $cdr
            (cdr-atom (' $partition-copy)))
        (- (copy-of-partition $partition $partition-copy))
        (+ (exec 5 $src $sink))))


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


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 6. Block support and block probability
;;
;; Source MeTTa equivalent:
;;
;;   (blk-prob $blk $db $total_count)
;;   = prob((cons-atom , $blk), db, total_count)
;;
;; MM2 needs one extra step:
;;
;;   indexed block -> real variable query -> count matches
;;
;; The generated query has the shape:
;;
;;   (, block-clause-1 block-clause-2 ...)
;;
;; The `count` sink writes:
;;
;;   (block-support $partition $indexed-block $support)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(exec 6
    (, (INPUT PATTERN ($pattern $pattern-support))
       (block $partition $indexed-block))
    (O
        ;; Keep the generated query visible for debugging.  These facts are
        ;; removed by cleanup after the final ISurp value is produced.
        (pure
            (debug-block-query $partition $indexed-block $query)
            $query
            (indices_to_vars
                (cons , (' $indexed-block))))

        ;; Create a real exec from the generated query.  When that exec runs it
        ;; counts support for this block.
        (pure
            (exec 6
                $query
                (O
                    (count
                        (block-support $partition $indexed-block $support)
                        $support
                        $query)))
            $query
            (indices_to_vars
                (cons , (' $indexed-block))))))


;; Direct fallback for common one-clause unary-style blocks:
;;
;;   ((Inheritance (var 0) man))
;;
;; Some current MORK/helper combinations do not materialize the dynamic
;; `indices_to_vars` query above for already-indexed input patterns.  This
;; fallback keeps support counting available for the common binary predicate
;; shape used in the newer ISurp integration tests.
(exec 6
    (, (block $partition (($rel (var $n) $arg))))
    (,
        (exec 6
            (, ($rel $x $arg))
            (O
                (count
                    (block-support $partition (($rel (var $n) $arg)) $support)
                    $support
                    ($rel $x $arg))))))


;; Convert each block support count into a probability.  This intentionally
;; divides by the full pattern total count, matching `isurp-old.metta`.
(exec 7
    (, (INPUT PATTERN ($pattern $pattern-support))
       (total-count-of $pattern $total-count)
       (block-support $partition $indexed-block $support))
    (O
        (pure
            (block-prob $partition $indexed-block $prob)
            $prob
            (f64_to_string
                (div_f64
                    (f64_from_string $support)
                    (f64_from_string $total-count))))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 6. Partition probability products
;;
;; Source MeTTa equivalent:
;;
;;   iprob_(partition, db, total_count)
;;     -> list of block probabilities
;;
;;   iprob(partition, db, total_count)
;;     -> product of those probabilities
;;
;; Current implementation status:
;;
;;   The validated `isurp-old` examples are 3-conjunct patterns.  Their
;;   partitions have either 2 or 3 blocks, so this file implements explicit
;;   product rules for those shapes.
;;
;;   To support arbitrary conjunct counts, replace these explicit product rules
;;   with a recursive product accumulator over `(block-prob ...)` facts.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Product for a two-block partition:
;;
;;   P(partition) = P(block-1) * P(block-2)
(exec 8
    (, (partition ($b1 $b2))
       (block-prob ($b1 $b2) $b1 $p1)
       (block-prob ($b1 $b2) $b2 $p2))
    (O
        (pure
            (partition-product ($b1 $b2) $product)
            $product
            (f64_to_string
                (product_f64
                    (f64_from_string $p1)
                    (f64_from_string $p2))))))


;; Product for a three-block partition:
;;
;;   P(partition) = P(block-1) * P(block-2) * P(block-3)
(exec 8
    (, (partition ($b1 $b2 $b3))
       (block-prob ($b1 $b2 $b3) $b1 $p1)
       (block-prob ($b1 $b2 $b3) $b2 $p2)
       (block-prob ($b1 $b2 $b3) $b3 $p3))
    (O
        (pure
            (partition-product ($b1 $b2 $b3) $product)
            $product
            (f64_to_string
                (product_f64
                    (product_f64
                        (f64_from_string $p1)
                        (f64_from_string $p2))
                    (f64_from_string $p3))))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 7. Expected interval [emin, emax]
;;
;; Source MeTTa equivalent:
;;
;;   $results = isurp-old_(partitions, db, total_count)
;;   ($emin $emax) = min-max($results)
;;
;; For a 3-conjunct old-isurp pattern there are four relevant partition product
;; values:
;;
;;   ((c1) (c2 c3))
;;   ((c1 c3) (c2))
;;   ((c1 c2) (c3))
;;   ((c1) (c2) (c3))
;;
;; This stage collects those four products and computes min/max.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(exec 9
    (, (indexed-pattern ($c1 $c2 $c3))
       (partition-product (($c1) ($c2 $c3)) $p1)
       (partition-product (($c1 $c3) ($c2)) $p2)
       (partition-product (($c1 $c2) ($c3)) $p3)
       (partition-product (($c1) ($c2) ($c3)) $p4))
    (O
        (pure
            (min-partition-product $min)
            $min
            (min-atom (' ($p1 $p2 $p3 $p4))))
        (pure
            (max-partition-product $max)
            $max
            (max-atom (' ($p1 $p2 $p3 $p4))))))


(exec 10
    (, (min-partition-product $min)
       (max-partition-product $max))
    (, (partition-product-range $min $max)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 8. Distance from interval
;;
;; Source MeTTa equivalent:
;;
;;   dst = dst_from_interval(emin, emax, pattern_prob)
;;
;; This stage spawns the reusable `dst-from-interval` definition, then the next
;; three execs select the matching case.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(exec 11
    (, (partition-product-range $emin $emax)
       (prob-of $pattern $emp)
       ((dst-from-interval $pattern $emin $emax $emp -> dst-of) $src $sink))
    (,
        (dst-request $pattern $emin $emax $emp dst-of)
        (exec 11 $src $sink)))


;; Case 1: empirical probability is above the interval.
(exec 12
    (, (dst-above? $pattern $emin $emax $emp $out true))
    (O
        (pure
            ($out $pattern $distance)
            $distance
            (f64_to_string
                (sub_f64
                    (f64_from_string $emp)
                    (f64_from_string $emax))))
        (- (dst-request $pattern $emin $emax $emp $out))
        (- (dst-above? $pattern $emin $emax $emp $out true))))


;; Case 2: empirical probability is below the interval.
(exec 12
    (, (dst-below? $pattern $emin $emax $emp $out true))
    (O
        (pure
            ($out $pattern $distance)
            $distance
            (f64_to_string
                (sub_f64
                    (f64_from_string $emin)
                    (f64_from_string $emp))))
        (- (dst-request $pattern $emin $emax $emp $out))
        (- (dst-below? $pattern $emin $emax $emp $out true))))


;; Case 3: empirical probability is inside the interval.
(exec 12
    (, (dst-inside? $pattern $emin $emax $emp $out true))
    (O
        (+ ($out $pattern 0.0))
        (- (dst-request $pattern $emin $emax $emp $out))
        (- (dst-inside? $pattern $emin $emax $emp $out true))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 9. Normalize or return raw distance
;;
;; Source MeTTa equivalent:
;;
;;   if normalize:
;;       min(dst / max(emax, pattern_prob), 1.0)
;;   else:
;;       min(dst, 1.0)
;;
;; The current old-isurp validation expects the normalized formula above.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Normalized denominator:
;;
;;   max(emax, pattern_prob)
(exec 13
    (, (INPUT NORMALIZATION TRUE)
       (dst-of $pattern $dst)
       (prob-of $pattern $prob)
       (partition-product-range $emin $emax))
    (O
        (pure
            (normalization-denom $pattern $dst $denom)
            $denom
            (max-atom (' ($emax $prob))))))


;; Normalized candidate:
;;
;;   dst / denominator
(exec 14
    (, (INPUT NORMALIZATION TRUE)
       (dst-of $pattern $dst)
       (normalization-denom $pattern $dst $denom))
    (O
        (pure
            (normalization-candidate $pattern $dst $candidate)
            $candidate
            (f64_to_string
                (div_f64
                    (f64_from_string $dst)
                    (f64_from_string $denom))))))


;; Final normalized output:
;;
;;   min(candidate, 1.0)
(exec 15
    (, (INPUT NORMALIZATION TRUE)
       (dst-of $pattern $dst)
       (normalization-denom $pattern $dst $denom)
       (normalization-candidate $pattern $dst $candidate))
    (O
        (pure
            (isurp-of $pattern $value)
            $value
            (min-atom (' ($candidate 1.0))))
        (- (normalization-denom $pattern $dst $denom))
        (- (normalization-candidate $pattern $dst $candidate))
        (- (dst-of $pattern $dst))))


;; Raw-distance output for `(INPUT NORMALIZATION FALSE)`.
;;
;; Source formula also caps raw distance at 1.0.  Existing validated values are
;; below 1.0, but we still apply the cap here for formula completeness.
(exec 16
    (, (INPUT NORMALIZATION FALSE)
       (dst-of $pattern $dst))
    (O
        (pure
            (isurp-of $pattern $value)
            $value
            (min-atom (' ($dst 1.0))))
        (- (dst-of $pattern $dst))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 10. pro-prob-wout-joint for newer ISurp
;;
;; Source PeTTa function:
;;
;;   (pro-prob-wout-joint $partition $db $db_ratio 1)
;;
;; MM2 public result:
;;
;;   (pro-prob-wout-joint-of $partition $prob)
;;
;; This multiplies empirical probabilities of partition blocks before applying
;; joint-variable correction with `eq-prob`.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(exec 13
    (, (INPUT DB-SIZE $db-size)
       (block-support $partition ($c1) $support))
    (O
        (pure
            (pro-block-prob $partition ($c1) $prob)
            $prob
            (f64_to_string
                (div_f64
                    (f64_from_string $support)
                    (f64_from_string $db-size))))))


(exec 13
    (, (INPUT DB-SIZE $db-size)
       (block-support $partition ($c1 $c2) $support))
    (O
        (pure
            (pro-block-universe-count $partition ($c1 $c2) $universe-count)
            $universe-count
            (i64_to_string
                (pow_i64
                    (i64_from_string $db-size)
                    (i64_from_string 2))))
        (pure
            (pro-block-prob $partition ($c1 $c2) $prob)
            $prob
            (f64_to_string
                (div_f64
                    (f64_from_string $support)
                    (f64_from_string
                        (i64_to_string
                            (pow_i64
                                (i64_from_string $db-size)
                                (i64_from_string 2)))))))))


(exec 13
    (, (INPUT DB-SIZE $db-size)
       (block-support $partition ($c1 $c2 $c3) $support))
    (O
        (pure
            (pro-block-universe-count $partition ($c1 $c2 $c3) $universe-count)
            $universe-count
            (i64_to_string
                (pow_i64
                    (i64_from_string $db-size)
                    (i64_from_string 3))))
        (pure
            (pro-block-prob $partition ($c1 $c2 $c3) $prob)
            $prob
            (f64_to_string
                (div_f64
                    (f64_from_string $support)
                    (f64_from_string
                        (i64_to_string
                            (pow_i64
                                (i64_from_string $db-size)
                                (i64_from_string 3)))))))))


(exec 14
    (, (partition ($b1))
       (pro-block-prob ($b1) $b1 $p1))
    (, (pro-prob-wout-joint-of ($b1) $p1)))


(exec 14
    (, (partition ($b1 $b2))
       (pro-block-prob ($b1 $b2) $b1 $p1)
       (pro-block-prob ($b1 $b2) $b2 $p2))
    (O
        (pure
            (pro-prob-wout-joint-of ($b1 $b2) $prob)
            $prob
            (f64_to_string
                (product_f64
                    (f64_from_string $p1)
                    (f64_from_string $p2))))))


(exec 14
    (, (partition ($b1 $b2 $b3))
       (pro-block-prob ($b1 $b2 $b3) $b1 $p1)
       (pro-block-prob ($b1 $b2 $b3) $b2 $p2)
       (pro-block-prob ($b1 $b2 $b3) $b3 $p3))
    (O
        (pure
            (pro-prob-wout-joint-of ($b1 $b2 $b3) $prob)
            $prob
            (f64_to_string
                (product_f64
                    (product_f64
                        (f64_from_string $p1)
                        (f64_from_string $p2))
                    (f64_from_string $p3))))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 11. ji-prob-est for newer ISurp
;;
;; Source PeTTa function:
;;
;;   (ji-prob-est $partition $pattern $db $db_ratio)
;;
;; MM2 public result:
;;
;;   (ji-prob-est-of $partition $prob)
;;
;; Formula:
;;
;;   ji-prob-est = pro-prob-wout-joint * eq-prob
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(exec 15
    (, (pro-prob-wout-joint-of $partition $independent-prob)
       (eq-prob-of $partition $eq-prob))
    (O
        (pure
            (ji-prob-est-of $partition $prob)
            $prob
            (f64_to_string
                (product_f64
                    (f64_from_string $independent-prob)
                    (f64_from_string $eq-prob))))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 12. do-ji-prob for newer ISurp
;;
;; Source PeTTa function:
;;
;;   (do-ji-prob $partitions $pattern $db $db_ratio)
;;
;; MM2 public result:
;;
;;   (do-ji-prob-of $partitions $prob-list)
;;
;; Input:
;;
;;   (do-ji-prob-request $partitions)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(exec 16
    (, (do-ji-prob-request ()))
    (, (do-ji-prob-of () ())))


(exec 16
    (, (do-ji-prob-request ($p1))
       (ji-prob-est-of $p1 $j1))
    (, (do-ji-prob-of ($p1) ($j1))))


(exec 16
    (, (do-ji-prob-request ($p1 $p2))
       (ji-prob-est-of $p1 $j1)
       (ji-prob-est-of $p2 $j2))
    (, (do-ji-prob-of ($p1 $p2) ($j1 $j2))))


(exec 16
    (, (do-ji-prob-request ($p1 $p2 $p3))
       (ji-prob-est-of $p1 $j1)
       (ji-prob-est-of $p2 $j2)
       (ji-prob-est-of $p3 $j3))
    (, (do-ji-prob-of ($p1 $p2 $p3) ($j1 $j2 $j3))))


(exec 16
    (, (do-ji-prob-request ($p1 $p2 $p3 $p4))
       (ji-prob-est-of $p1 $j1)
       (ji-prob-est-of $p2 $j2)
       (ji-prob-est-of $p3 $j3)
       (ji-prob-est-of $p4 $j4))
    (, (do-ji-prob-of ($p1 $p2 $p3 $p4) ($j1 $j2 $j3 $j4))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 13. emp-prob-pbs without sampling
;;
;; Source PeTTa function:
;;
;;   (emp-prob-pbs $pattern $db $prob-estimate $db-ratio)
;;
;; MM2 scope:
;;
;;   Sampling/bootstrap logic is intentionally not ported.  This always computes
;;   direct empirical probability:
;;
;;     support(pattern) / DB-SIZE ^ number-of-conjuncts(pattern)
;;
;; MM2 public result:
;;
;;   (emp-prob-pbs-of $pattern $prob)
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(exec 30
    (, (INPUT DB-SIZE $db-size)
       (INPUT PATTERN ((, $c1) $support)))
    (O
        (pure
            (emp-prob-pbs-of (, $c1) $prob)
            $prob
            (f64_to_string
                (div_f64
                    (f64_from_string $support)
                    (f64_from_string $db-size))))))


(exec 17
    (, (INPUT DB-SIZE $db-size)
       (INPUT PATTERN ((, $c1 $c2) $support)))
    (O
        (pure
            (emp-prob-pbs-universe-count (, $c1 $c2) $universe-count)
            $universe-count
            (i64_to_string
                (pow_i64
                    (i64_from_string $db-size)
                    (i64_from_string 2))))
        (pure
            (emp-prob-pbs-of (, $c1 $c2) $prob)
            $prob
            (f64_to_string
                (div_f64
                    (f64_from_string $support)
                    (f64_from_string
                        (i64_to_string
                            (pow_i64
                                (i64_from_string $db-size)
                                (i64_from_string 2)))))))))


(exec 17
    (, (INPUT DB-SIZE $db-size)
       (INPUT PATTERN ((, $c1 $c2 $c3) $support)))
    (O
        (pure
            (emp-prob-pbs-universe-count (, $c1 $c2 $c3) $universe-count)
            $universe-count
            (i64_to_string
                (pow_i64
                    (i64_from_string $db-size)
                    (i64_from_string 3))))
        (pure
            (emp-prob-pbs-of (, $c1 $c2 $c3) $prob)
            $prob
            (f64_to_string
                (div_f64
                    (f64_from_string $support)
                    (f64_from_string
                        (i64_to_string
                            (pow_i64
                                (i64_from_string $db-size)
                                (i64_from_string 3)))))))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 10. Cleanup
;;
;; ISurp creates many temporary facts.  Once `(isurp-of pattern value)` exists,
;; cleanup tasks are generated and then consumed by generic cleanup execs.
;;
;; The final `isurp-of` result is intentionally kept.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(exec 17
    (, (isurp-of $pattern $value))
    (,
        (cleanup (block $partition $block))
        (cleanup (partition $partition))
        (cleanup (block-support $partition $block $support))
        (cleanup (block-prob $partition $block $prob))
        (cleanup (partition-product $partition $product))
        (cleanup (min-partition-product $min))
        (cleanup (max-partition-product $max))
        (cleanup (partition-product-range $min $max))
        (cleanup (indexed-pattern $indexed-pattern))
        (cleanup (partitions-of $indexed-pattern $indexed-partition))
        (cleanup (copy-of-partition $partition $partition-copy))
        (cleanup (debug-block-query $partition $block $query))
        (cleanup (dst-above? $p $emin $emax $emp $out $above))
        (cleanup (dst-below? $p $emin $emax $emp $out $below))
        (cleanup (dst-inside? $p $emin $emax $emp $out $inside))
        (cleanup (dst-request $p $emin $emax $emp $out))
        (cleanup (normalization-denom $p $dst $denom))
        (cleanup (normalization-candidate $p $dst $candidate))))


;; Remove a selected fact and its cleanup request.  This exec writes itself back
;; so it can keep cleaning until no matching cleanup task remains.
(exec 31
    (, (cleanup $fact) $fact)
    (O
        (- (cleanup $fact))
        (- $fact)
        (+ (exec 31
            (, (cleanup $f) $f)
            (O
                (- (cleanup $f))
                (- $f))))))


;; Remove cleanup requests whose target facts are already absent.
(exec 32
    (, (cleanup $fact))
    (O
        (- (cleanup $fact))
        (+ (exec 32
            (, (cleanup $f))
            (O
                (- (cleanup $f)))))))
