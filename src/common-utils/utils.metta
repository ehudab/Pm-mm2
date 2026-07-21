;;===============================================================
;; Function definitions
;;===============================================================

;; Count all db facts in the main db.
((count-db $db-name -> $out)
    (, ($db-name $fact))
    (O
        (count ($out $db-name $count) $count $fact)))

;; Count conjuncts in a pattern.
((count-conjuncts $pattern -> $out)
    (, (INPUT PATTERN ($pattern $support)))
    (O
        (pure
            ($out $pattern $count)
            $count
            (size-atom
                (cdr-atom (' $pattern))))))

;; How many ways can we choose k items from n items, without caring about order.
;; total-counts(pattern, db) = db_size! / (num_conjuncts! * (db_size - num_conjuncts)!)
;; C(n, k) = falling_factorial(n, k) / k!
((total-counts $db $pattern -> $out)
    (, (INPUT DB-SIZE $n)
       (num-of-conjuncts $pattern $k))
    (O
        (pure
            (total-count-of $pattern $total)
            $total
            (i64_to_string
                (div_i64
                    (falling_factorial
                        (i64_from_string $n)
                        (i64_from_string $k))
                    (factorial
                        (i64_from_string $k)))))))
                        

;; Compute the probability of a pattern by dividing the support by total counts.
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

;; Distance from an empirical value to an interval [emin, emax].
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