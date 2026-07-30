;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; 0. Input bootstrap
;;
;; This module prepares facts that later ISurp modules consume, but it does not
;; generate partitions.
;;
;; Responsibilities:
;;
;;   1. Start common utility execs when their function definitions are loaded.
;;   2. Normalize raw pattern variables into indexed markers:
;;
;;        $x, $y, ... -> (var 0), (var 1), ...
;;
;; Generated partitions need stable variable identity across blocks.  Later,
;; `indices_to_vars` converts these markers back into real MM2 variables for
;; support-count queries.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


(exec (surp 010 bootstrap-definitions)
    (, (INPUT DB $db-name)
       (INPUT PATTERN ($pattern $support))
       ((count-db $db-name -> db-size) $src-of-count $sink-of-count)
       ((count-conjuncts $pattern -> num-of-conjuncts) $src-of-cnj $sink-of-cnj)
       ((total-counts $db-name $pattern -> total-count-of) $src-of-tc $sink-of-tc)
       ((prob $pattern $db-name -> prob-of) $src-of-prob $sink-of-prob))
    (O
        ;; Optional DB-size count path.  The current `total-counts` definition
        ;; uses `INPUT DB-SIZE`, but this fact can help with debugging.
        (+ (exec (surp 011 count-db) $src-of-count $sink-of-count))

        ;; Count clauses in the input comma pattern.
        (+ (exec (surp 012 count-conjuncts) $src-of-cnj $sink-of-cnj))

        ;; Compute C(db_size, number_of_conjuncts).
        (+ (exec (surp 013 total-counts) $src-of-tc $sink-of-tc))

        ;; Compute empirical pattern probability from the provided support.
        (+ (exec (surp 014 prob) $src-of-prob $sink-of-prob))))


;; The generic `vars_to_indices` helper does not reliably index variables after
;; the input pattern has already been captured by an exec variable, so the active
;; rules below index the common miner pattern shape directly:
;;
;;   (, ($rel1 $x $arg1) ($rel2 $x $arg2) ...)
;;      -> (($rel1 (var 0) $arg1) ($rel2 (var 0) $arg2) ...)
;;
;; The repeated `$x` in the source side is a real MORK variable, so these rules
;; only fire when the same input variable is shared across the clauses.
(exec (surp 020 index-pattern-1)
    (, (INPUT PATTERN ((, ($rel1 $x $arg1)) $support)))
    (, (indexed-pattern (($rel1 (var 0) $arg1)))
       (indexed-pattern-of (, ($rel1 $x $arg1)) (($rel1 (var 0) $arg1)))))

(exec (surp 020 index-pattern-2)
    (, (INPUT PATTERN ((, ($rel1 $x $arg1)
                           ($rel2 $x $arg2)) $support)))
    (, (indexed-pattern (($rel1 (var 0) $arg1)
                         ($rel2 (var 0) $arg2)))
       (indexed-pattern-of (, ($rel1 $x $arg1)
                              ($rel2 $x $arg2))
                           (($rel1 (var 0) $arg1)
                            ($rel2 (var 0) $arg2)))))

(exec (surp 020 index-pattern-3)
    (, (INPUT PATTERN ((, ($rel1 $x $arg1)
                           ($rel2 $x $arg2)
                           ($rel3 $x $arg3)) $support)))
    (, (indexed-pattern (($rel1 (var 0) $arg1)
                         ($rel2 (var 0) $arg2)
                         ($rel3 (var 0) $arg3)))
       (indexed-pattern-of (, ($rel1 $x $arg1)
                              ($rel2 $x $arg2)
                              ($rel3 $x $arg3))
                           (($rel1 (var 0) $arg1)
                            ($rel2 (var 0) $arg2)
                            ($rel3 (var 0) $arg3)))))
