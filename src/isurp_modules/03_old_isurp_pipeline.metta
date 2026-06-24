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
;; 10. Cleanup
;;
;; ISurp creates many temporary facts.  Once `(isurp-of pattern value)` exists,
;; cleanup tasks are generated and then consumed by generic cleanup execs.
;;
;; The final `isurp-of` result is intentionally kept.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(exec 30
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
