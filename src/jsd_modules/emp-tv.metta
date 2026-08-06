;;===============================================================
;; Function definitions
;;===============================================================


((sup-num-query $pattern $priority $db)
    (, (sup-num-query $pattern $db $query) (exec $priority $src (O (pure $out $var (tuple db-fact $db (car $q))))))
    (O
        (pure
            (exec $priority
                (,)
                (O
                    (pure
                        (sup-num-query $pattern $db $new-query)
                        $new-query
                        (cons (' ($n $query)))
                    )
                    (- (sup-num-query $pattern $db $query))
                    (+ (exec $priority $src (O (pure $out $var (tuple db-fact $db (car (cdr $q)))))))
                )
            )
            $n
            (tuple db-fact $db (car (' $pattern)))
        )
        
    )
)
;; Get total relevant items
((universe-count $db $pattern -> $out)
    (, (num-of-conjuncts $pattern $pattern-count) (db-size $db $db-count)) 
    (O 
        (pure 
            ($out $pattern $db $universe-count)
            $universe-count
            (i64_to_string (pow_i64 (i64_from_string $db-count) (i64_from_string $pattern-count)))
        )
    )
)

;; =======================================================================================================================


(exec (jsd 110 sup-num-query)
    (, (block $partition $block) ((sup-num-query $block (jsd 110 sup-num-query) $db) $src $sink) (INPUT DB $db))
    (, (exec (jsd 110 sup-num-query) $src $sink) (sup-num-query $block $db ()))
)

(exec (jsd 111 sup-num)
    (, (block $partition $block) (sup-num-query $block $db $q) (INPUT DB $db))
    (O
        (pure
            (exec (jsd 111 sup-num)
                $query
                (O
                    (count 
                        (support-of $block $db $sup)
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

(exec (jsd 112 universe-count)
    (, (INPUT DB $db-name) (support-of $block $db-name $support)
         ((count-conjuncts $block -> num-of-conjuncts) $src-of-cnj $sink-of-cnj)
         ((universe-count $db-name $block -> universe-count-of) $src-of-uvc $sink-of-uvc))
         
    (O 
        (+ (exec (jsd 113 count-conjuncts) $src-of-cnj $sink-of-cnj))
        (+ (exec (jsd 114 universe-count) $src-of-uvc $sink-of-uvc))
    )

)


(exec (jsd 115 emp-tv-confidence)
    (, (universe-count-of $pattern $db $uc) (CONSTANT DEFAULT_K $k))
    (O
        (pure
            (emp-tv-confidence $pattern $db $conf)
            $conf
            (f32_to_string ( product_f32 
                (f32_from_string 0.1) 
                (div_f32 (f32_from_string $uc) (sum_f32 (f32_from_string $uc) (f32_from_string $k)))))
        )
    )
)
(exec (jsd 116 emp-tv-mean)
    (, (universe-count-of $pattern $db $uc) (support-of $pattern $db $support))
    (O
        (pure
            (emp-tv-mean $pattern $db $mean)
            $mean
            (f32_to_string (div_f32 (f32_from_string $support) (f32_from_string $uc)))
        )
    )
)
(exec (jsd 117 emp-tv)
    (, (emp-tv-confidence $pattern $db $conf) (emp-tv-mean $pattern $db $mean))
    (, (EMPTV $pattern $db ($mean $conf)))
)