;; Generic triplet-only conjunction expansion for the MM2 pattern miner.
;;
;; The working representation is indexed:
;;
;;   (Inheritance $x human)  ->  (Inheritance (var 0) human)
;;
;; Indexed conjuncts are saved and expanded at every frequent level. Support
;; counting converts each indexed conjunct back into a real MM2 query with
;; indices_to_vars, so repeated variables are respected by the count sink.

;;===============================================================
;; Function definitions
;;===============================================================

;; Generate support-count execs for all queued candidates.
;;
;; Input:
;;   (ce-pending $size $candidate)
;;
;; Output:
;;   (ce-support $size $candidate $support)
(DEF ce-support-fn
    (, (ce-pending $size $candidate)
       (DEF ce-support-to-i32-fn $support-to-i32-p $support-to-i32-t)
       (DEF ce-support-pass-fn $support-pass-p $support-pass-t)
       (DEF ce-save-pass-fn $save-pass-p $save-pass-t)
       (DEF ce-drop-fail-fn $drop-fail-p $drop-fail-t)
       (DEF ce-expand-size-to-i32-fn $expand-size-p $expand-size-t)
       (DEF ce-expand-pass-fn $expand-pass-p $expand-pass-t)
       (DEF ce-expand-todo-fn $expand-todo-p $expand-todo-t)
       (DEF ce-drop-expand-fn $drop-expand-p $drop-expand-t)
       (DEF ce-build-candidate-fn $build-candidate-p $build-candidate-t)
       (DEF ce-canonical-fn $canonical-p $canonical-t)
       (DEF ce-candidate-size-fn $candidate-size-p $candidate-size-t)
       (DEF ce-candidate-size-to-i32-fn $candidate-size-i32-p $candidate-size-i32-t)
       (DEF ce-candidate-pass-fn $candidate-pass-p $candidate-pass-t)
       (DEF ce-queue-candidate-fn $queue-candidate-p $queue-candidate-t)
       (DEF ce-drop-candidate-fn $drop-candidate-p $drop-candidate-t))
    (O
        (- (ce-pending $size $candidate))
        (pure
            (exec (CE 1 1)
                $query
                (O
                    (count
                        (ce-support $size $candidate $support)
                        $support
                        $query)))
            $query
            (indices_to_vars
                (cons , (' $candidate))))

        ;; Schedule the rest of this expansion cycle. These execs are added as
        ;; data, then consumed in priority order after the support-count execs.
        (+ (exec (CE 2 0) $support-to-i32-p $support-to-i32-t))
        (+ (exec (CE 2 1) $support-pass-p $support-pass-t))
        (+ (exec (CE 2 2) $save-pass-p $save-pass-t))
        (+ (exec (CE 2 3) $drop-fail-p $drop-fail-t))

        (+ (exec (CE 3 0) $expand-size-p $expand-size-t))
        (+ (exec (CE 3 1) $expand-pass-p $expand-pass-t))
        (+ (exec (CE 3 2) $expand-todo-p $expand-todo-t))
        (+ (exec (CE 3 3) $drop-expand-p $drop-expand-t))

        (+ (exec (CE 4 0) $build-candidate-p $build-candidate-t))
        (+ (exec (CE 4 1) $canonical-p $canonical-t))
        (+ (exec (CE 4 2) $candidate-size-p $candidate-size-t))
        (+ (exec (CE 4 3) $candidate-size-i32-p $candidate-size-i32-t))
        (+ (exec (CE 4 4) $candidate-pass-p $candidate-pass-t))
        (+ (exec (CE 4 5) $queue-candidate-p $queue-candidate-t))
        (+ (exec (CE 4 6) $drop-candidate-p $drop-candidate-t))))

;; Convert a text support count into an i32 value for comparison.
(DEF ce-support-to-i32-fn
    (, (ce-support $size $candidate $support))
    (O
        (pure
            (ce-support-i32 $size $candidate $support $support-i32)
            $support-i32
            (i32_from_string $support))
        (- (ce-support $size $candidate $support))))

;; Compare support against the configured threshold.
(DEF ce-support-pass-fn
    (, (ce-support-i32 $size $candidate $support $support-i32)
       (ce-threshold-i32 $threshold $threshold-i32))
    (O
        (pure
            (ce-support-pass $size $candidate $support $pass)
            $pass
            (ge_i32 $support-i32 $threshold-i32))
        (- (ce-support-i32 $size $candidate $support $support-i32))))

;; Save every frequent conjunct. These facts are the component's main output.
(DEF ce-save-pass-fn
    (, (ce-support-pass $size $candidate $support true))
    (O
        (+ (ce-conjunct $size $candidate $support))
        (+ (expanded-conjunct $size $candidate $support))
        (+ (ce-expand-check $size $candidate $support))
        (- (ce-support-pass $size $candidate $support true))))

;; Drop candidates that did not pass the support threshold.
(DEF ce-drop-fail-fn
    (, (ce-support-pass $size $candidate $support false))
    (O
        (- (ce-support-pass $size $candidate $support false))))

;; Convert the current conjunct size so it can be compared with max depth.
(DEF ce-expand-size-to-i32-fn
    (, (ce-expand-check $size $candidate $support))
    (O
        (pure
            (ce-expand-size-i32 $size $candidate $support $size-i32)
            $size-i32
            (i32_from_string $size))))

;; Only conjuncts smaller than depth-of-conjunct are expanded further.
(DEF ce-expand-pass-fn
    (, (ce-expand-check $size $candidate $support)
       (ce-expand-size-i32 $size $candidate $support $size-i32)
       (ce-max-depth-i32 $max-depth $max-depth-i32))
    (O
        (pure
            (ce-expand-pass $size $candidate $pass)
            $pass
            (lt_i32 $size-i32 $max-depth-i32))
        (- (ce-expand-check $size $candidate $support))
        (- (ce-expand-size-i32 $size $candidate $support $size-i32))))

;; Queue a frequent conjunct for expansion when it is still below max depth.
(DEF ce-expand-todo-fn
    (, (ce-expand-pass $size $candidate true))
    (O
        (+ (ce-expand-todo $size $candidate))
        (- (ce-expand-pass $size $candidate true))))

;; Drop frequent conjuncts that are already at max depth.
(DEF ce-drop-expand-fn
    (, (ce-expand-pass $size $candidate false))
    (O
        (- (ce-expand-pass $size $candidate false))))

;; Build a candidate by unioning the singleton base triplet with the current
;; conjunct. The one-argument union-atom form is deliberate: the full pair is
;; the final quoted argument, so compound triplets are passed as data instead of
;; being evaluated as grounded calls.
(DEF ce-build-candidate-fn
    (, (ce-expand-todo $old-size $conjunct)
       (ce-base $base))
    (O
        (pure
            (ce-raw-candidate $old-size $raw)
            $raw
            (union-atom (' (($base) $conjunct))))
        (- (ce-expand-todo $old-size $conjunct))))

;; Canonicalize candidate order. This makes (A B) and (B A) collapse to one fact.
(DEF ce-canonical-fn
    (, (ce-raw-candidate $old-size $raw))
    (O
        (pure
            (ce-candidate $old-size $candidate)
            $candidate
            (sort-atom (' $raw)))
        (- (ce-raw-candidate $old-size $raw))))

;; Record the candidate's new size.
(DEF ce-candidate-size-fn
    (, (ce-candidate $old-size $candidate))
    (O
        (pure
            (ce-candidate-size $old-size $candidate $size)
            $size
            (size-atom (' $candidate)))
        (- (ce-candidate $old-size $candidate))))

;; Convert the old and new sizes so filtering is staged.
(DEF ce-candidate-size-to-i32-fn
    (, (ce-candidate-size $old-size $candidate $size))
    (O
        (pure
            (ce-candidate-size-i32 $candidate $size $size-i32)
            $size-i32
            (i32_from_string $size))
        (pure
            (ce-candidate-old-size-i32 $candidate $size $old-size-i32)
            $old-size-i32
            (i32_from_string $old-size))))

;; Keep only candidates that actually grew and are within depth-of-conjunct.
(DEF ce-candidate-pass-fn
    (, (ce-candidate-size $old-size $candidate $size)
       (ce-candidate-size-i32 $candidate $size $size-i32)
       (ce-candidate-old-size-i32 $candidate $size $old-size-i32)
       (ce-max-depth-i32 $max-depth $max-depth-i32))
    (O
        (pure
            (ce-candidate-depth-pass $candidate $size $pass)
            $pass
            (le_i32 $size-i32 $max-depth-i32))
        (pure
            (ce-candidate-growth-pass $candidate $size $growth-pass)
            $growth-pass
            (gt_i32 $size-i32 $old-size-i32))
        (- (ce-candidate-size $old-size $candidate $size))
        (- (ce-candidate-size-i32 $candidate $size $size-i32))
        (- (ce-candidate-old-size-i32 $candidate $size $old-size-i32))))

;; Queue passing candidates and schedule another support-count cycle.
(DEF ce-queue-candidate-fn
    (, (ce-candidate-depth-pass $candidate $size true)
       (ce-candidate-growth-pass $candidate $size true)
       (DEF ce-support-fn $support-p $support-t))
    (O
        (+ (ce-pending $size $candidate))
        (+ (exec (CE 1 0) $support-p $support-t))
        (- (ce-candidate-depth-pass $candidate $size true))
        (- (ce-candidate-growth-pass $candidate $size true))))

;; Drop candidates that exceed max depth or did not grow.
(DEF ce-drop-candidate-fn
    (, (ce-candidate-depth-pass $candidate $size $depth-pass)
       (ce-candidate-growth-pass $candidate $size $growth-pass))
    (O
        (- (ce-candidate-depth-pass $candidate $size $depth-pass))
        (- (ce-candidate-growth-pass $candidate $size $growth-pass))))

;;===============================================================
;; Pipeline
;;===============================================================

;; Convert threshold and max depth once. The binary values are intentionally
;; opaque in dumps; they are only used by later grounded comparisons.
(exec (CE 0 0)
    (, (support-threshold $threshold)
       (depth-of-conjunct $max-depth))
    (O
        (pure
            (ce-threshold-i32 $threshold $threshold-i32)
            $threshold-i32
            (i32_from_string $threshold))
        (pure
            (ce-max-depth-i32 $max-depth $max-depth-i32)
            $max-depth-i32
            (i32_from_string $max-depth))))

;; Accept only triplet-format pattern atoms. Each singleton candidate is queued
;; so the same support/filter/expand machinery handles level 1 and later levels.
(exec (CE 0 1)
    (, (pattern 0 ($predicate $left $right)))
    (O
        (pure
            (ce-base $indexed)
            $indexed
            (vars_to_indices (' ($predicate $left $right)))
        )
        (pure
            (ce-pending 1 ($indexed))
            $indexed
            (vars_to_indices (' ($predicate $left $right)))
        )))

;; Start the first support-count cycle after all bases have been normalized.
(exec (CE 0 2)
    (, (DEF ce-support-fn $support-p $support-t))
    (O
        (+ (exec (CE 1 0) $support-p $support-t))))

;;===============================================================
;; Demo inputs
;;===============================================================

;; Keep this bottom section small and replace it with caller inputs when this
;; file is used as a library.

(pattern 0 (Inheritance $x human))
(pattern 0 (Inheritance $x $y))
(pattern 0 (Inheritance $x ugly))
(pattern 0 (Inheritance $x sodaDrinker))

(depth-of-conjunct 3)
(support-threshold 2)

(Inheritance Allen human)
(Inheritance Allen ugly)
(Inheritance Allen sodaDrinker)
(Inheritance Bob human)
(Inheritance Bob ugly)
(Inheritance Cason human)
(Inheritance Cason sodaDrinker)
(Inheritance Dana human)
(Inheritance Dana ugly)
(Inheritance Dana sodaDrinker)
