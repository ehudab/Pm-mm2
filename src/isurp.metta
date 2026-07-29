(INPUT DB db1)
(INPUT PATTERN ((, (inheritance $x man) (inheritance $x ugly)) 8 ))
(INPUT PATTERN ((, (inheritance $x $w) (inheritance $x $y) (inheritance $x $z)) 8 ))
(INPUT PATTERN ((, (inheritance $x $y) (inheritance $x $z)) 8 ))
(INPUT PATTERN ((, (inheritance $x woman) (inheritance $x ugly) (inheritance $x sodaDrinker)) 8 ))

(EXPECTED-RESULT ji_prob_est_interval (, (inheritance $a man) (inheritance $a ugly)) (0.0004629629629629629 0.0004629629629629629))
(EXPECTED-RESULT ji_prob_est_interval (, (inheritance $a $b) (inheritance $a $c)) (0.016666666666666666 0.016666666666666666))
(EXPECTED-RESULT ji_prob_est_interval (, (inheritance $a woman) (inheritance $a ugly) (inheritance $a sodaDrinker)) (1.2860082304526748e-6 3.858024691358025e-6))
(EXPECTED-RESULT ji_prob_est_interval (, (inheritance $a $b) (inheritance $a $c) (inheritance $a $d)) (0.0002777777777777778 0.0008796296296296296))





(exec (isurp 001 db-size)
    (, (INPUT DB $db) (db-fact $db $value))
    (O (count (db-size $db $db-size) $db-size ($value)))
)


;; Index pattern before partitions
(exec (isurp 002 indexed-pattern)
    (, (INPUT PATTERN ($pattern $support)))
    (O
        (pure
            (indexed-pattern $indexed-copy)
            $indexed-copy
            (vars_to_indices (cdr-atom (' $pattern)))
        )    
    )
)   

(exec (isurp 003 partitions)
    (, (indexed-pattern $indexed-pattern))
    (O
        (pure
            (partitions-of $indexed-pattern $indexed-partition)
            $indexed-partition
            (partitions (' $indexed-pattern))))
)


;; Copy partitions before expanding them into single partition then blocks/subpatterns.
(exec (isurp 004 copy-partitions)
    (, (partitions-of $pattern $partitions))
    (, (copy-partitions $partitions $partitions))
)
(exec (isurp 005 extract-partition)
    (, (copy-partitions $partitions $copy-partitions) (exec (isurp 005 extract-partition) $src $sink))
    (O
        (pure
            (partition $partitions $partition)
            $partition
            (car (' $copy-partitions))
        )
        (- (copy-partitions $partitions $copy-partitions))
        (pure
            (copy-partitions $partitions $less-partitions) 
            $less-partitions
            (cdr (' $copy-partitions))
        )
        (+ (exec (isurp 005 extract-partition) $src $sink))
    )
)


(exec (isurp 006 copy-partition)
    (, (partition $partitions $partition))
    (, (copy-partition $partition $partition))
)

(exec (isurp 007 extract-subpattern)
    (, (copy-partition $partition $copy-partition) (exec (isurp 007 extract-subpattern) $src $sink))
    (O
        (pure
            (subpattern $partition $subpattern)
            $subpattern
            (car (' $copy-partition))
        )
        (- (copy-partition $partition $copy-partition))
        (pure
            (copy-partition $partition $less-partition)
            $less-partition
            (cdr (' $copy-partition))
        )
        (+ (exec (isurp 007 extract-subpattern) $src $sink))
    )
)



; Copy subpatterns to extract expressions and variables
(exec (isurp 008 copy-subpattern)
    (, (subpattern $partition $subpattern))
    (, (copy-subpattern $subpattern $subpattern))
)

(exec (isurp 009 extract-expression)
    (, (copy-subpattern $subpattern $copy-subpattern) (exec (isurp 009 extract-expression) $src $sink))
    (O
        (pure
            (expression $subpattern $expression)
            $expression
            (car (' $copy-subpattern))
        )
        (- (copy-subpattern $subpattern $copy-subpattern))
        (pure
            (copy-subpattern $subpattern $less-subpattern)
            $less-subpattern
            (cdr (' $copy-subpattern))
        )
        (+ (exec (isurp 009 extract-expression) $src $sink))
    )
)


;; Extracting variables from single expressions
(exec (isurp 010 copy-expression)
    (, (expression $subpattern $expression))
    (, (copy-expression $expression $expression))
)

(exec (isurp 011 check-if-variable)
    (, (copy-expression $expr $main-expr) (exec (isurp 011 check-if-variable) $src $sink))
    (O
        (pure
            (first-element-is-var $expr $bool from $main-expr)
            $bool
            (i8_to_string (is_var (first (' $expr))))
        )
        (pure
            (copy-expression $less-expr $main-expr)
            $less-expr
            (cdr (' $expr))
        )
        (- (copy-expression $expr $main-expr))
        (+ (exec (isurp 011 check-if-variable) $src $sink))
        (- (first-element-is-var $expr 0 from $main-expr))
    )
)

(exec (isurp 012 extract-variable)
    (, (first-element-is-var $less-expr 1 from $main-expr))
    (O
        (pure
            (var-of $main-expr $var)
            $var
            (car (' $less-expr))
        )
        (- (first-element-is-var $less-expr 1 from $main-expr))
        
    )
)

(exec (isurp 012 collect-variable-of-subpattern)
    (, (var-of $expression $var) (expression $subpattern $expression))
    (, (var-of $subpattern $var))
)

;; Counting number of subpatterns from a partition that a particular variable appears in not the total count of appearance
(exec (isurp 013 count-subpatterns-containing-var)
    (, (var-of $subpattern $var) (subpattern $partition $subpattern))
    (O
        (count
            (appears-in $var $partition $count)
            $count
            ($partition $subpattern)
        )
    )
)


;; Extracting variables that appear in at least 2 subpattern in a partition
(exec (isurp 014 extract-variables-with-min-appearance)
    (, (appears-in $var $partition $count))
    (O
        (pure
            (appears-in-ge-2 $var $partition $bool)
            $bool
            (ge_i64 (i64_from_string $count) (i64_from_string 2))
        )
        (- (appears-in-ge-2 $var $partition false))
    )
)




; --------------------------------------------------------------------------------------------------------
;; Note: joint-vars in Petta implementation returns all unique vars 

;; Save as joint-var
; (exec (isurp 015 joint-var)
;     (, (appears-in-ge-2 $var $partition true))
;     (O (- (appears-in-ge-2 $var $partition true)) (+ (joint-var $partition $var)))
; )

;; Extracting subpatterns that have the variables that appear at least twice in a partition
; (exec (isurp 016 connected-subpatterns-with-var)
;     (, (joint-var $partition $var) (subpattern $partition $subpattern) (var-of $subpattern $var))
;     (, (connected-subpatterns-with-var $partition $var $subpattern))
; )
; ---------------------------------------------------------------------------------------------------------


(exec (isurp 015 joint-var)
    (, (appears-in-ge-2 $var $partition true))
    (O (- (appears-in-ge-2 $var $partition true)))
)


(exec (isurp 016 connected-subpatterns-with-var)
    (, (subpattern $partition $subpattern) (var-of $subpattern $var))
    (, (connected-subpatterns-with-var $partition $var $subpattern))
)


;; ---------------
;; Since find-most-specialized-abstract always returns (is-blk-more-abstract is not defined) it always falls back to db size.
;; ---------------

; Processing blocks in a partition

(exec (isurp 020 process-blocks)
    (, (partition $partitions $partition) (INPUT DB $db) (db-size $db $db-size) (connected-subpatterns-with-var $partition $var $subpattern))
    (O 
        (count
            (exec (isurp 020 process-blocks)
                (,)
                (O
                    (pure
                        (processed-blocks $partition $var $p)
                        $p
                        (f64_to_string (div_f64
                            (f64_from_string 1)
                            (i64_as_f64 (pow_i64 (i64_from_string $db-size) (sub_i64 (i64_from_string $num) (i64_from_string 1))))  ))
                    )
                )
            )
            $num
            ($subpattern)
        )
        )
)


; Extracting final probability after processing all variables
(exec (isurp 020 calculate-prob-for-vars-1)
    (, (processed-blocks $partition $var $p))
    (O 
        (count 
            ((calculate-prob-for-vars $partition) $count () false)
            $count
            ($var $p)
        )
    )
)

(exec (isurp 020 calculate-prob-for-vars-2)
    (, (processed-blocks $partition $var $processed) ((calculate-prob-for-vars $partition) $count $elements false) (exec (isurp 020 calculate-prob-for-vars-2) $src $sink))
    (O
        (pure
            (exec (isurp 020 calculate-prob-for-vars-2)
                (, )
                (O
                    (pure
                        (exec (isurp 020 calculate-prob-for-vars-2)
                            (,)
                            (O (+ ((calculate-prob-for-vars $partition) $count $new-elements $is-last)) (- ((calculate-prob-for-vars $partition) $count $elements false)) (+ (exec (isurp 020 calculate-prob-for-vars-2) $src $sink)))
                        )
                        $is-last
                        (le_i64 (i64_from_string $count) (i64_from_string (size-atom (' $new-elements))))
                    )
                )
            )
            $new-elements
            (sort-math (cons $processed (' $elements)))
        )
    ) 
)

(exec (isurp 020 calculate-prob-for-vars-3)
    (, (processed-blocks $partition $var $processed) ((calculate-prob-for-vars $partition) $count $elements true))
    (O
        (pure 
            (is-member $processed $elements $bool)
            $bool
            (is-member $processed (' $elements))
        )
    )
)

(exec (isurp 020 calculate-prob-for-vars-4)
    (, (is-member $processed $elements false) (processed-blocks $partition $var $processed) ((calculate-prob-for-vars $partition) $count $elements true))
    (O (- ((calculate-prob-for-vars $partition) $count $elements true)))
)
(exec (isurp 020 calculate-prob-for-vars-5)
    (, ((calculate-prob-for-vars $partition) $count $elements true) (is-member $a $b $c))
    (O  (-((calculate-prob-for-vars $partition) $count $elements true)) (- (is-member $a $b $c))
        (pure
            (calculate-prob-for-vars $partition $uniques $uniques 1)
            $uniques
            (unique-atom (' $elements))
        )
    )
)
(exec (isurp 020 calculate-prob-for-vars-6)
    (, (calculate-prob-for-vars $partition $nums $tail-nums $p) (exec (isurp 020 calculate-prob-for-vars-6) $src $sink))
    (O
        (pure
            (exec (0)
                (,)
                (O
                    (pure
                        (calculate-prob-for-vars $partition $nums $tail $new-p)
                        $tail
                        (cdr (' $tail-nums))
                    )
                    (- (calculate-prob-for-vars $partition $nums $tail-nums $p))
                    (+ (exec (isurp 020 calculate-prob-for-vars-6) $src $sink))
                )
            )
            $new-p
            (f64_to_string (product_f64 (f64_from_string $p) (f64_from_string (car (' $tail-nums)))))
        )
    )
)

(exec (isurp 021 eq-prob)
    (, (calculate-prob-for-vars $partition $nums () $p))
    (, (eq-prob $partition $p))
)

;; Copying & unindexing subpatterns to calculate their support and saving it as the same format used by common-utils

(exec (isurp 021 unindexing-subpattern)
    (, (subpattern $partition $subpattern))
    (O
        (pure
            (subpattern-var-ind $var-subpattern $subpattern)
            $var-subpattern
            (indices_to_vars (' $subpattern))
        )
    )
)



(exec (isurp 022 count-subpattern-support)
    (, (subpattern-var-ind ($blk) $pattern) (INPUT DB $db) (db-fact $db $blk))
    (O
        (count
            (exec (isurp 022 count-subpattern-support)
                (,)
                (O
                    (pure
                        (support ($f-pattern $support))
                        $f-pattern
                        (cons , (' $pattern))
                    )
                )
            )
            $support
            ($blk)
        )
        (- (subpattern-var-ind ($blk) $pattern))
    )
)
(exec (isurp 022 count-subpattern-support)
    (, (subpattern-var-ind ($blk-1 $blk-2) $pattern) (INPUT DB $db) (db-fact $db $blk-1) (db-fact $db $blk-2))
    (O
        (count
            (exec (isurp 022 count-subpattern-support)
                (,)
                (O
                    (pure
                        (support ($f-pattern $support))
                        $f-pattern
                        (cons , (' $pattern))
                    )
                )
            )
            $support
            ($blk-1 $blk-2)
        )
        (- (subpattern-var-ind ($blk-1 $blk-2) $pattern))
    )
)


(exec (isurp 023 universe-count)
    (, (INPUT DB $db-name) (support ($pattern $support))
         ((count-conjuncts $pattern -> num-of-conjuncts) $src-of-cnj $sink-of-cnj)
         ((universe-count $db-name $pattern -> universe-count-of) $src-of-uvc $sink-of-uvc))
         

    (O 
        (+ (exec (0) $src-of-cnj $sink-of-cnj))
        (+ (exec (1) $src-of-prob $sink-of-prob))
        (+ (exec (2) $src-of-uvc $sink-of-uvc))
    )

)

;; Computes the empirical probability of a pattern in a Corpus
(exec (isurp 024 universe-count)
    (, (support ($pattern $support)) (universe-count-of $pattern $universe-count))
    (O
        (pure
            (emp-prob-of $pattern $emp-prob)
            $emp-prob
            (f64_to_string (div_f64 (f64_from_string $support) (f64_from_string $universe-count)))
        )
    )
)

;; Computing the product probability of subpatterns while ignoring dependencies between joint variables (treats components as independent)
(exec (isurp 025 pro-prob-wout-joint-1)
    (, (partition $pattern $partition))
    (, (pro-prob-wout-joint $partition $partition 1))
)
(exec (isurp 026 pro-prob-wout-joint-2)
    (, (pro-prob-wout-joint $partition $copy-par $prod) (exec (isurp 026 pro-prob-wout-joint-2) $src $sink))
    (O
        (pure
            (exec (isurp 026 pro-prob-wout-joint-2)
                (, (emp-prob-of $head $emp-prob))
                (O (pure
                    (exec (isurp 026 pro-prob-wout-joint-2) (,) 
                    (O 
                        (pure 
                            (pro-prob-wout-joint $partition $tail $new-prod) 
                            $new-prod 
                            (f64_to_string (product_f64 (f64_from_string $emp-prob) (f64_from_string $prod)))
                        )
                        (+ (exec (isurp 026 pro-prob-wout-joint-2) $src $sink))
                        (- (pro-prob-wout-joint $partition $copy-par $prod))))
                    $tail
                    (cdr (' $copy-par))
                )
            )
            )
            $head
            (cons , (car (' $copy-par)))
        )
        
    )
)

(exec (isurp 027 pro-prob-wout-joint-3)
    (, (pro-prob-wout-joint $partition $tail $new-prod))
    (O (- (pro-prob-wout-joint $partition $tail $new-prod)) (+ (pro-prob-wout-joint $partition $new-prod)))
)

;; Compute Joint-Independent Probability Estimate
(exec (isurp 028 ji-prob-est)
    (, (pro-prob-wout-joint $partition $ppwj-prob) (eq-prob $partition $eq-prob))
    (O
        (pure
            (ji-prob-est $partition $jpe-prob)
            $jpe-prob
            (f64_to_string (product_f64 (f64_from_string $ppwj-prob) (f64_from_string $eq-prob)))
        ))
)

;; computes joint independent probabilities for a pattern
(exec (isurp 029 do-ji-prob-1)
    (, (partition $partitions $partition))
    (, (do-ji-prob $partitions $partitions ()))
)



(exec (isurp 030 do-ji-prob-2)
    (, (do-ji-prob $partitions $tail $jpe-probs) (exec (isurp 030 do-ji-prob-2) $src $sink))
    (O
        (pure
            (exec (0)
                (, (ji-prob-est $partition $jpe-prob))
                (O
                    (pure
                        (exec (0)
                            (,)
                            (O
                                (pure
                                    (do-ji-prob $partitions $new-tail $new-jpe-probs)
                                    $new-jpe-probs
                                    (sort-math (cons $jpe-prob (' $jpe-probs)))
                                )
                                (- (do-ji-prob $partitions $tail $jpe-probs))
                                (+ (exec (isurp 030 do-ji-prob-2) $src $sink))
                            )
                        )
                        $new-tail
                        (cdr (' $tail))
                    )
                    
                )
            )
            $partition
            (car (' $tail))
        )
    )
)

(exec (isurp 031 do-ji-prob-3)
    (, (do-ji-prob $partitions () $jpe-probs))
    (O
        (- (do-ji-prob $partitions () $jpe-probs))
        (+ (do-ji-prob $partitions $jpe-probs))
    )
)
(exec (isurp 032 ji-prob-est-interval)
    (, (do-ji-prob $partitions $jpe-probs))
    (O
        (pure
            (exec (isurp 032 ji-prob-est-interval)
                (,)
                (O
                    (pure
                        (exec (isurp 033 ji-prob-est-interval)
                            (, (partitions-of $indexed-pattern $partitions))
                            (O
                                (pure
                                    (ji_prob_est_interval $pat ($min $max))
                                    $pat
                                    (indices_to_vars (cons , (' $indexed-pattern)))
                                )
                            )
                        )
                        $max
                        (last (' $jpe-probs))
                    )
                )
            )
            $min
            (first (' $jpe-probs))
        )
    )
)


                        













;; Final cleanup: 
 
(exec (isurp 990 cleanup)
    (, (ji_prob_est_interval $jpei-pattern ($min $max)))
    (,
        (cleanup (indexed-pattern $indexed-copy))
        (cleanup (partitions-of $indexed-pattern $indexed-partition))
        (cleanup (partition $partitions $partition))
        (cleanup (subpattern $partition $subpattern))
        (cleanup (expression $subpattern $expression))
        (cleanup (var-of $main-expr $var))
        (cleanup (appears-in $var $partition $count))
        (cleanup (joint-var $partition $var))
        (cleanup (connected-subpatterns-with-var $partition $var $subpattern))
        (cleanup (value-count $to-var $var $subpattern))
        (cleanup (value-count-of $subpattern $var-ind $count))
        (cleanup (processed-blocks $partition $var $p))
        (cleanup (calculate-prob-for-vars $partition $nums $tail $p))
        (cleanup (eq-prob $partition $prod))
        (cleanup (subpattern-var-ind $var-subpattern $subpattern))
        (cleanup (support ($f-pattern $support)))
        (cleanup (num-of-conjuncts $pattern $coun))
        (cleanup (universe-count-of $pattern $universe-count))
        (cleanup (emp-prob-of $pattern $emp-prob))
        (cleanup (pro-prob-wout-joint $partition $new-prod))
        (cleanup (ji-prob-est $partition $jpe-prob))
        (cleanup (do-ji-prob $partitions $jpe-probs))
    )
)


;; One cleanup matcher removes any fact selected by the cleanup task.
(exec (isurp 991 cleanup)
    (, (cleanup $fact) $fact)
    (O
        (- (cleanup $fact))
        (- $fact)
        ))

;; Remove the generic cleanup tasks after they are no longer useful.
(exec (isurp 992 cleanup)
    (, (cleanup $fact))
    (O
        (- (cleanup $fact))
        ))
;;===============================================================
;; Function definitions
;;===============================================================

;; Count all db facts in the main db.
((count-db $db -> $out)
    (, (db-fact $db $fact))
    (O
        (count ($out $db $count) $count $fact)))

;; Count conjuncts in a pattern.
((count-conjuncts $pattern -> $out)
    (, (support ($pattern $support)))
    (O
        (pure
            ($out $pattern $count)
            $count
            (size-atom
                (cdr-atom (' $pattern))))))


;; Get total relevant items
((universe-count $db $pattern -> $out)
    (, (num-of-conjuncts $pattern $pattern-count) (db-size $db $db-count)) 
    (O 
        (pure 
            ($out $pattern $universe-count)
            $universe-count
            (i64_to_string (pow_i64 (i64_from_string $db-count) (i64_from_string $pattern-count)))
        )
    )
)

               


(db-fact db1 (inheritance name_Allen human))
(db-fact db1 (inheritance name_Abe human))
(db-fact db1 (inheritance name_Cason human))
(db-fact db1 (inheritance name_Davion human))
(db-fact db1 (inheritance name_Hessley human))
(db-fact db1 (inheritance name_Jadrian human))
(db-fact db1 (inheritance name_Rio human))
(db-fact db1 (inheritance name_Bob human))
(db-fact db1 (inheritance name_Mike human))
(db-fact db1 (inheritance name_Zac human))
(db-fact db1 (inheritance name_Lily human))
(db-fact db1 (inheritance name_Emily human))
(db-fact db1 (inheritance name_Lucy human))
(db-fact db1 (inheritance name_Sophia human))
(db-fact db1 (inheritance name_Alaura human))
(db-fact db1 (inheritance name_Breonna human))
(db-fact db1 (inheritance name_Jaleesa human))
(db-fact db1 (inheritance name_Jassy human))
(db-fact db1 (inheritance name_Jenica human))
(db-fact db1 (inheritance name_Kecia human))
(db-fact db1 (inheritance name_Allen man))
(db-fact db1 (inheritance name_Abe man))
(db-fact db1 (inheritance name_Cason man))
(db-fact db1 (inheritance name_Davion man))
(db-fact db1 (inheritance name_Hessley man))
(db-fact db1 (inheritance name_Jadrian man))
(db-fact db1 (inheritance name_Rio man))
(db-fact db1 (inheritance name_Bob man))
(db-fact db1 (inheritance name_Mike man))
(db-fact db1 (inheritance name_Zac man))
(db-fact db1 (inheritance name_Lily woman))
(db-fact db1 (inheritance name_Emily woman))
(db-fact db1 (inheritance name_Lucy woman))
(db-fact db1 (inheritance name_Sophia woman))
(db-fact db1 (inheritance name_Alaura woman))
(db-fact db1 (inheritance name_Breonna woman))
(db-fact db1 (inheritance name_Jaleesa woman))
(db-fact db1 (inheritance name_Jassy woman))
(db-fact db1 (inheritance name_Jenica woman))
(db-fact db1 (inheritance name_Kecia woman))
(db-fact db1 (inheritance name_Allen ugly))
(db-fact db1 (inheritance name_Abe ugly))
(db-fact db1 (inheritance name_Cason ugly))
(db-fact db1 (inheritance name_Davion ugly))
(db-fact db1 (inheritance name_Hessley ugly))
(db-fact db1 (inheritance name_Lily ugly))
(db-fact db1 (inheritance name_Emily ugly))
(db-fact db1 (inheritance name_Lucy ugly))
(db-fact db1 (inheritance name_Sophia ugly))
(db-fact db1 (inheritance name_Alaura ugly))
(db-fact db1 (inheritance name_Allen sodaDrinker))
(db-fact db1 (inheritance name_Abe sodaDrinker))
(db-fact db1 (inheritance name_Cason sodaDrinker))
(db-fact db1 (inheritance name_Davion sodaDrinker))
(db-fact db1 (inheritance name_Hessley sodaDrinker))
(db-fact db1 (inheritance name_Breonna sodaDrinker))
(db-fact db1 (inheritance name_Jaleesa sodaDrinker))
(db-fact db1 (inheritance name_Jassy sodaDrinker))
(db-fact db1 (inheritance name_Jenica sodaDrinker))
(db-fact db1 (inheritance name_Kecia sodaDrinker))



;; =====================
;; Further tests if needed
;; =====================

; (INPUT PATTERN ((, (inheritance $x woman) (inheritance $x sodaDrinker)) 8 ))
; (INPUT PATTERN ((, (inheritance $x human) (inheritance $x $y)) 8 ))
; (INPUT PATTERN ((, (inheritance $x man) (inheritance $x sodaDrinker)) 8 ))
; (INPUT PATTERN ((, (inheritance $x $y) (inheritance $x ugly)) 8 ))
; (INPUT PATTERN ((, (inheritance $x woman) (inheritance $x $z)) 8 ))
; (INPUT PATTERN ((, (inheritance $x human) (inheritance $x man) (inheritance $x ugly)) 8 ))
; (INPUT PATTERN ((, (inheritance $x human) (inheritance $x woman) (inheritance $x sodaDrinker)) 8 ))
; (INPUT PATTERN ((, (inheritance $x sodaDrinker) (inheritance $x $z) (inheritance $x man)) 8 ))
; (INPUT PATTERN ((, (inheritance $x man) (inheritance $x ugly) (inheritance $x sodaDrinker)) 8 ))
; (INPUT PATTERN ((, (inheritance $x $y) (inheritance $x $z) (inheritance $x human)) 8 ))

; (EXPECTED-RESULT ji_prob_est_interval (, (inheritance $a woman) (inheritance $a sodaDrinker)) (0.0004629629629629629 0.0004629629629629629))
; (EXPECTED-RESULT ji_prob_est_interval (, (inheritance $a human) (inheritance $a $b)) (0.005555555555555555 0.005555555555555555))
; (EXPECTED-RESULT ji_prob_est_interval (, (inheritance $a man) (inheritance $a sodaDrinker)) (0.0004629629629629629 0.0004629629629629629))
; (EXPECTED-RESULT ji_prob_est_interval (, (inheritance $a $b) (inheritance $a ugly)) (0.0027777777777777775 0.0027777777777777775))
; (EXPECTED-RESULT ji_prob_est_interval (, (inheritance $a woman) (inheritance $a $b)) (0.0027777777777777775 0.0027777777777777775))
; (EXPECTED-RESULT ji_prob_est_interval (, (inheritance $a human) (inheritance $a man) (inheritance $a ugly)) (2.5720164609053496e-6 7.71604938271605e-6))
; (EXPECTED-RESULT ji_prob_est_interval (, (inheritance $a human) (inheritance $a woman) (inheritance $a sodaDrinker)) (2.5720164609053496e-6 7.71604938271605e-6))
; (EXPECTED-RESULT ji_prob_est_interval (, (inheritance $a sodaDrinker) (inheritance $a $b) (inheritance $a man)) (7.71604938271605e-6 2.700617283950617e-5))
; (EXPECTED-RESULT ji_prob_est_interval (, (inheritance $a man) (inheritance $a ugly) (inheritance $a sodaDrinker)) (1.2860082304526748e-6 3.858024691358025e-6))
; (EXPECTED-RESULT ji_prob_est_interval (, (inheritance $a $b) (inheritance $a $c) (inheritance $a human)) (9.259259259259259e-5 0.0002932098765432098))