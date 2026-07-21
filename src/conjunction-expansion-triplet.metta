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
       (DEF ce-schedule-support-filter-fn $support-filter-p $support-filter-t)
       (DEF ce-schedule-expansion-check-fn $expansion-check-p $expansion-check-t)
       (DEF ce-build-candidate-fn $build-candidate-p $build-candidate-t)
       (DEF ce-schedule-candidate-result-fn $candidate-result-p $candidate-result-t))
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
                (cons , ($candidate))))
        ;; Compact schedulers keep template substitution below MORK's variable
        ;; limit while preserving the original stage ordering.
        (+ (exec (CE 2 0) $support-filter-p $support-filter-t))
        (+ (exec (CE 3 0) $expansion-check-p $expansion-check-t))
        (+ (exec (CE 4 0) $build-candidate-p $build-candidate-t))
        (+ (exec (CE 6 0) $candidate-result-p $candidate-result-t))))
;; Schedule support conversion, thresholding, saving, and failure cleanup after
;; support-count execs have materialized ce-support facts.
(DEF ce-schedule-support-filter-fn
    (, (ce-support $size $candidate $support)
       (DEF ce-support-pass-fn $support-pass-p $support-pass-t)
       (DEF ce-save-pass-fn $save-pass-p $save-pass-t))
    
    (O
        (+ (exec (CE 2 2) $support-pass-p $support-pass-t))
        (+ (exec (CE 2 3) $save-pass-p $save-pass-t))    ))

;; Schedule depth checking and expansion queueing for every frequent conjunct.
(DEF ce-schedule-expansion-check-fn
    (, (ce-expand-check $size $candidate $support)
       (DEF ce-expand-pass-fn $expand-pass-p $expand-pass-t)
       (DEF ce-expand-todo-fn $expand-todo-p $expand-todo-t)
       (DEF ce-drop-expand-fn $drop-expand-p $drop-expand-t))
    (O
        (+ (exec (CE 3 2) $expand-pass-p $expand-pass-t))
        (+ (exec (CE 3 3) $expand-todo-p $expand-todo-t))
        (+ (exec (CE 3 4) $drop-expand-p $drop-expand-t))))
  (DEF ce-drop-candidate-fn
    (, (ce-candidate-depth-pass $candidate $size $depth-pass)
       (ce-candidate-growth-pass $candidate $size $growth-pass))
    (O
        (- (ce-candidate-depth-pass $candidate $size $depth-pass))
        (- (ce-candidate-growth-pass $candidate $size $growth-pass))))
;; Start the trusted canonicalize/size/filter/queue chain only after every
;; connected raw candidate has been emitted.
(DEF ce-schedule-candidate-result-fn
    (, (ce-raw-candidate $old-size $raw)
       (DEF ce-sort-candidate-fn $sort-candidate-p $sort-candidate-t)
       (DEF ce-candidate-to-vars-fn $candidate-vars-p $candidate-vars-t)
       (DEF ce-alpha-candidate-fn $alpha-candidate-p $alpha-candidate-t)
       (DEF ce-candidate-size-fn $candidate-size-p $candidate-size-t)
       (DEF ce-candidate-pass-fn $candidate-pass-p $candidate-pass-t)
       (DEF ce-queue-candidate-fn $queue-candidate-p $queue-candidate-t)
       (DEF ce-drop-candidate-fn $drop-candidate-p $drop-candidate-t))
    (O
        (+ (exec (CE 6 1) $sort-candidate-p $sort-candidate-t))
        (+ (exec (CE 6 2) $candidate-vars-p $candidate-vars-t))
        (+ (exec (CE 6 3) $alpha-candidate-p $alpha-candidate-t))
        (+ (exec (CE 6 4) $candidate-size-p $candidate-size-t))
        (+ (exec (CE 6 6) $candidate-pass-p $candidate-pass-t))
        (+ (exec (CE 6 7) $queue-candidate-p $queue-candidate-t))
        (+ (exec (CE 6 8) $drop-candidate-p $drop-candidate-t))))

;; Compare support against the configured threshold.



(DEF ce-support-pass-fn
    (,(ce-support $size $candidate $support)
       (support-threshold $threshold)
    )
    (O
        (pure
            (ce-support-pass $size $candidate $support $pass)
            $pass
            (ge_i32  (i32_from_string $support)  (i32_from_string  $threshold)))
     (ce-support $size $candidate $support)))
;; Save every frequent conjunct. These facts are the component's main output.
(DEF ce-save-pass-fn
    (, (ce-support-pass $size $candidate $support true))
    (O
        (+ (ce-conjunct $size $candidate $support))
        (+ (expanded-conjunct $size $candidate $support))
        (+ (ce-expand-check $size $candidate $support))
        (- (ce-support-pass $size $candidate $support true))))
;; Only conjuncts smaller than depth-of-conjunct are expanded further.
(DEF ce-expand-pass-fn
    (, (ce-expand-check $size $candidate $support)
       (ce-max-depth-i32 $max-depth $max-depth-i32))
    (O
        (pure
            (ce-expand-pass $size $candidate $pass)
            $pass

            (lt_i32 (i32_from_string $size) $max-depth-i32)
            )
        (- (ce-expand-check $size $candidate $support))
       ))
      
;; Queue a frequent conjunct for expansion when it is still below max depth.
(DEF ce-expand-todo-fn
    (, (ce-expand-pass $size $candidate true))
    (O
        (+ (ce-expand-todo $size $candidate))
        (- (ce-expand-pass $size $candidate true))))

;; Orchestrate connected candidate construction through small schedulers. Their
;; capture sets stay below MORK's 64-variable rule limit even after nested DEF
;; substitution. Every substage remains gated on the active ce-expand-todo so
;; stale intermediate facts can never be replayed by a later support cycle.
(DEF ce-build-candidate-fn
    (, (ce-expand-todo $old-size $conjunct)
       (DEF ce-schedule-pair-build-fn $pair-build-p $pair-build-t)
       (DEF ce-schedule-choice-build-fn $choice-build-p $choice-build-t)
       (DEF ce-schedule-map-build-fn $map-build-p $map-build-t)
       (DEF ce-schedule-output-build-fn $output-build-p $output-build-t))
    (O
        (+ (exec (CE 4 1) $pair-build-p $pair-build-t))
        (+ (exec (CE 4 1) $choice-build-p $choice-build-t))
        (+ (exec (CE 4 1) $map-build-p $map-build-t))
        (+ (exec (CE 4 1) $output-build-p $output-build-t))))
;; Schedule expansion-pair creation, dynamic atom extraction, and base shape
;; classification. Scheduler rules never consume the active todo.
(DEF ce-schedule-pair-build-fn
    (, (ce-expand-todo $old-size $conjunct)
       (DEF ce-expand-pair-fn $expand-pair-p $expand-pair-t)
       (DEF ce-expand-pair-details-fn $pair-details-p $pair-details-t)
       (DEF ce-expand-pair-scan-fn $pair-scan-p $pair-scan-t)
       (DEF ce-conjunct-var-check-fn $conjunct-var-check-p $conjunct-var-check-t)
       (DEF ce-base-shape-fn $base-shape-p $base-shape-t))
    (O
        (+ (exec (CE 4 2) $expand-pair-p $expand-pair-t))
        (+ (exec (CE 4 3) $pair-details-p $pair-details-t))
        (+ (exec (CE 4 4) $pair-scan-p $pair-scan-t))
        (+ (exec (CE 4 5) $conjunct-var-check-p $conjunct-var-check-t))
        (+ (exec (CE 4 6) $base-shape-p $base-shape-t))))

;; Schedule existing/fresh choices and repeated-source classification.
(DEF ce-schedule-choice-build-fn
    (, (ce-expand-todo $old-size $conjunct)
       (DEF ce-existing-choice-fn $existing-choice-p $existing-choice-t)
       (DEF ce-drop-non-var-fn $drop-non-var-p $drop-non-var-t)
       (DEF ce-fresh-candidate-fn $fresh-candidate-p $fresh-candidate-t)
       (DEF ce-drop-existing-fresh-fn $drop-existing-fresh-p $drop-existing-fresh-t)
       (DEF ce-save-fresh-choice-fn $save-fresh-choice-p $save-fresh-choice-t)
       (DEF ce-base-source-indices-to-i32-fn $source-indices-p $source-indices-t)
       (DEF ce-base-source-relation-fn $source-relation-p $source-relation-t))
    (O
        (+ (exec (CE 4 7) $existing-choice-p $existing-choice-t))
        (+ (exec (CE 4 7) $drop-non-var-p $drop-non-var-t))
        (+ (exec (CE 4 8) $fresh-candidate-p $fresh-candidate-t))
        (+ (exec (CE 4 9) $drop-existing-fresh-p $drop-existing-fresh-t))
        (+ (exec (CE 5 0) $save-fresh-choice-p $save-fresh-choice-t))
        (+ (exec (CE 5 1) $source-indices-p $source-indices-t))
        (+ (exec (CE 5 2) $source-relation-p $source-relation-t))))

;; Schedule position mappings and their connectivity classification.
(DEF ce-schedule-map-build-fn
    (, (ce-expand-todo $old-size $conjunct)
       (DEF ce-build-same-var-map-fn $same-var-map-p $same-var-map-t)
       (DEF ce-build-distinct-var-map-fn $distinct-var-map-p $distinct-var-map-t)
       (DEF ce-build-left-var-map-fn $left-var-map-p $left-var-map-t)
       (DEF ce-build-right-var-map-fn $right-var-map-p $right-var-map-t)
       (DEF ce-check-map-connectivity-fn $map-connectivity-p $map-connectivity-t)
       (DEF ce-connect-map-fn $connect-map-p $connect-map-t)
       (DEF ce-drop-disconnected-map-fn $drop-disconnected-map-p $drop-disconnected-map-t))
    (O
        (+ (exec (CE 5 3) $same-var-map-p $same-var-map-t))
        (+ (exec (CE 5 3) $distinct-var-map-p $distinct-var-map-t))
        (+ (exec (CE 5 3) $left-var-map-p $left-var-map-t))
        (+ (exec (CE 5 3) $right-var-map-p $right-var-map-t))
        (+ (exec (CE 5 4) $map-connectivity-p $map-connectivity-t))
        (+ (exec (CE 5 5) $connect-map-p $connect-map-t))
        (+ (exec (CE 5 5) $drop-disconnected-map-p $drop-disconnected-map-t))))

;; Schedule connected-base construction, raw fan-out, and final cleanup.
(DEF ce-schedule-output-build-fn
    (, (ce-expand-todo $old-size $conjunct)
       (DEF ce-build-connected-base-fn $connected-base-p $connected-base-t)
       (DEF ce-build-raw-candidate-fn $raw-candidate-p $raw-candidate-t)
       (DEF ce-cleanup-var-choice-fn $cleanup-var-choice-p $cleanup-var-choice-t))
    (O
        (+ (exec (CE 5 6) $connected-base-p $connected-base-t))
        (+ (exec (CE 5 7) $raw-candidate-p $raw-candidate-t))
        (+ (exec (CE 5 8) $cleanup-var-choice-p $cleanup-var-choice-t))))
;; Pair every expandable conjunct with every normalized base pattern.
;; create pair with the posible one only not with all 
;; Merged function that pairs AND filters in one step  
(DEF ce-expand-pair-fn
    (, (ce-expand-todo $old-size $conjunct)
       (ce-base $base))
    (O
        (+ (ce-expand-pair $old-size $conjunct $base))))
;; Start a cursor over the complete conjunct and classify the base's two
;; argument slots once. The cursor carries the original conjunct so facts from
;; concurrent expansion pairs cannot be mixed.
(DEF ce-expand-pair-details-fn
    (, (ce-expand-todo $old-size $conjunct)
       (ce-expand-pair $old-size $conjunct
           ($predicate $base-left $base-right)))
    (O
        (+ (ce-expand-pair-scan
            $old-size
            $conjunct
            ($predicate $base-left $base-right)
            $conjunct))
))
;; Emit the head atom, replace the remaining list with its tail, and schedule
;; another pass. car-atom/cdr-atom fail on the empty tail; that last pass only
;; removes the exhausted cursor and lets the next scheduler stage begin.
(DEF ce-expand-pair-scan-fn
    (, (ce-expand-todo $old-size $conjunct)
       (ce-expand-pair-scan $old-size $conjunct $base $remaining)
       (DEF ce-expand-pair-scan-fn $pair-scan-p $pair-scan-t))
    (O
        (pure
            (ce-conjunct-atom
                $old-size $conjunct $base $atom)
            $atom
            (car-atom (' $remaining)))
        (pure
            (ce-expand-pair-scan
                $old-size $conjunct $base $rest)
            $rest
            (cdr-atom (' $remaining)))
        (- (ce-expand-pair-scan
            $old-size $conjunct $base $remaining))
        (+ (exec (CE 4 4) $pair-scan-p $pair-scan-t))))

;; Record whether each conjunct argument is an indexed variable. Constants are
;; retained in the conjunct but are not variable choices for a new base.
        
      
(DEF ce-conjunct-var-check-fn
    (, (ce-expand-todo $old-size $conjunct)
       (ce-conjunct-atom
           $old-size
           $conjunct
           $base
           ($predicate $left $right)))
    (O
        (pure
            (ce-conjunct-var-check
                $old-size $conjunct $base $left $left-is-var)
            $left-is-var
            (i8_to_string (is_var ( $left))))
        (pure
            (ce-conjunct-var-check
                $old-size $conjunct $base $right $right-is-var)
            $right-is-var
            (i8_to_string (is_var ($right)))
        
        )
        (- (ce-conjunct-atom
            $old-size
            $conjunct
            $base
            ($predicate $left $right)))))

;; Join the two base-slot checks into one shape fact. Later mapping rules use
;; the flags to replace only variable slots and preserve constants verbatim.

(DEF ce-base-shape-fn
    (, (ce-expand-todo $old-size $conjunct)
       (ce-base-left-check $old-size $conjunct $base $left-is-var)
       (ce-base-right-check $old-size $conjunct $base $right-is-var))
    (O
        (+ (ce-base-shape
            $old-size $conjunct $base $left-is-var $right-is-var))
        (- (ce-base-left-check
            $old-size $conjunct $base $left-is-var))
        (- (ce-base-right-check
            $old-size $conjunct $base $right-is-var))))


(DEF ce-drop-non-var-fn
    (, (ce-expand-todo $old-size $conjunct)
      (ce-conjunct-var-check $old-size $conjunct $base $constant 0)
)
    (O
        (- (ce-conjunct-var-check
            $old-size $conjunct $base $constant 0))))

;; Increment every existing variable index to propose fresh candidates. Because
;; MM2 indexing is contiguous, removing proposals that already exist leaves the
;; single next variable marker, with no depth-sized successor table.
(DEF ce-fresh-candidate-fn
    (, (ce-expand-todo $old-size $conjunct)
      (ce-conjunct-var-check $old-size $conjunct $base (var $index) 1))
    (O
        (pure
            (ce-fresh-candidate
                $old-size $conjunct $base (var $successor))
            $successor
            (i32_to_string
                (sum_i32
                    (i32_from_string $index)
                    (i32_one))))
                (- (ce-conjunct-var-check
            $old-size $conjunct $base $var 1))
                
                ))

(DEF ce-drop-existing-fresh-fn
    (, (ce-expand-todo $old-size $conjunct)
       (ce-fresh-candidate $old-size $conjunct $base $candidate)
       (ce-var-choice $old-size $conjunct $base $candidate existing))
    (O
        (- (ce-fresh-candidate
            $old-size $conjunct $base $candidate))))

(DEF ce-save-fresh-choice-fn
    (, (ce-expand-todo $old-size $conjunct)
       (ce-fresh-candidate $old-size $conjunct $base $fresh))
    (O
        (+ (ce-var-choice $old-size $conjunct $base $fresh fresh))
        (- (ce-fresh-candidate $old-size $conjunct $base $fresh))))


    
;; For a two-variable base, remember whether both slots came from the same
;; source variable. Equal source variables must remain equal after replacement.

(DEF ce-base-source-relation-fn
    (, (ce-expand-todo $old-size $conjunct)
     (ce-base-shape
           $old-size
           $conjunct
           ($predicate (var $left-index) (var $right-index))
           1
           1)
    )
    (O
        (pure
            (ce-base-source-same
                $old-size
                $conjunct
                $base
                $same)
            $same
            (eq_i32  (i32_from_string $left-index) (i32_from_string $right-index))) ))

;; A repeated source variable has one choice shared by both output positions.
(DEF ce-build-same-var-map-fn
    (, (ce-expand-todo $old-size $conjunct)
       (ce-base-source-same $old-size $conjunct $base true)
       (ce-var-choice $old-size $conjunct $base $out $kind))
    (O
        (+ (ce-base-var-map
            $old-size $conjunct $base $out $kind $out $kind))))

;; Distinct source variables take the cross product of the available choices.
(DEF ce-build-distinct-var-map-fn
    (, (ce-expand-todo $old-size $conjunct)
       (ce-base-source-same $old-size $conjunct $base false)
       (ce-var-choice $old-size $conjunct $base $left-out $left-kind)
       (ce-var-choice $old-size $conjunct $base $right-out $right-kind))
    (O
        (+ (ce-base-var-map
            $old-size
            $conjunct
            $base
            $left-out
            $left-kind
            $right-out
            $right-kind))))

;; When only one base slot is variable, map that slot and keep the other slot's
;; constant unchanged.
(DEF ce-build-left-var-map-fn
    (, (ce-expand-todo $old-size $conjunct)
       (ce-base-shape
           $old-size
           $conjunct
           ($predicate $left-source $right-constant)
           1
           0)
       (ce-var-choice
           $old-size
           $conjunct
           ($predicate $left-source $right-constant)
           $left-out
           $left-kind))
    (O
        (+ (ce-base-var-map
            $old-size
            $conjunct
            ($predicate $left-source $right-constant)
            $left-out
            $left-kind
            $right-constant
            constant))))

(DEF ce-build-right-var-map-fn
    (, (ce-expand-todo $old-size $conjunct)
       (ce-base-shape
           $old-size
           $conjunct
           ($predicate $left-constant $right-source)
           0
           1)
       (ce-var-choice
           $old-size
           $conjunct
           ($predicate $left-constant $right-source)
           $right-out
           $right-kind))
    (O
        (+ (ce-base-var-map
            $old-size
            $conjunct
            ($predicate $left-constant $right-source)
            $left-constant
            constant
            $right-out
            $right-kind))))

;; Connectivity is true when at least one mapped base slot uses an existing
;; conjunct variable. Source-kind facts turn that OR into a small pure max.
(DEF ce-check-map-connectivity-fn
    (, (ce-expand-todo $old-size $conjunct)
       (ce-base-var-map
           $old-size
           $conjunct
           $base
           $left-out
           $left-kind
           $right-out
           $right-kind)
       (ce-source-connectivity $left-kind $left-connected)
       (ce-source-connectivity $right-kind $right-connected))
    (O
        (pure
            (ce-base-var-map-connectivity
                $old-size
                $conjunct
                $base
                $left-out
                $right-out
                $connected)
            $connected
            (i8_to_string
                (max_i8
                    (i8_from_string $left-connected)
                    (i8_from_string $right-connected))))
        (- (ce-base-var-map
            $old-size
            $conjunct
            $base
            $left-out
            $left-kind
            $right-out
            $right-kind))))
(DEF ce-connect-map-fn
    (, (ce-expand-todo $old-size $conjunct)
       (ce-base-var-map-connectivity
           $old-size $conjunct $base $left-out $right-out 1))
    (O
        (+ (ce-connected-map
            $old-size $conjunct $base $left-out $right-out))
        (- (ce-base-var-map-connectivity
            $old-size $conjunct $base $left-out $right-out 1))))

(DEF ce-drop-disconnected-map-fn
    (, (ce-expand-todo $old-size $conjunct)
       (ce-base-var-map-connectivity
           $old-size $conjunct $base $left-out $right-out 0))
    (O
        (- (ce-base-var-map-connectivity
            $old-size $conjunct $base $left-out $right-out 0))))

;; Rebuild the triplet after mapping its variable positions.
(DEF ce-build-connected-base-fn
    (, (ce-expand-todo $old-size $conjunct)
       (ce-connected-map
           $old-size
           $conjunct
           ($predicate $base-left $base-right)
           $left-out
           $right-out))
    (O
        (+ (ce-connected-base
            $old-size
            $conjunct
            ($predicate $left-out $right-out)))
        (- (ce-connected-map
            $old-size
            $conjunct
            ($predicate $base-left $base-right)
            $left-out
            $right-out))))

;; Union every connected base variant with the old conjunct. The one-argument
;; union-atom form is deliberate: the full pair is passed as quoted data.
(DEF ce-build-raw-candidate-fn
    (, (ce-expand-todo $old-size $conjunct)
       (ce-connected-base $old-size $conjunct $connected-base))
    (O
        (pure
            (ce-raw-candidate $old-size $raw)
            $raw
            (union-atom (' (($connected-base) $conjunct))))
        (- (ce-connected-base
            $old-size $conjunct $connected-base))))

;; Remove pair-scoped build facts after raw-candidate fan-out. The active todo
;; is removed last, including when an expansion produced no connected variant.
(DEF ce-cleanup-var-choice-fn
    (, (ce-expand-todo $old-size $conjunct)
       (ce-var-choice $old-size $conjunct $base $var $kind)
       (ce-base-shape $old-size $conjunct $base $left-is-var $right-is-var) 
       (ce-base-source-same $old-size $conjunct $base $same) 
       (ce-expand-pair $old-size $conjunct $base)
       )
    (O
        (- (ce-var-choice $old-size $conjunct $base $var $kind))
        (- (ce-base-shape $old-size $conjunct $base $left-is-var $right-is-var))
        (- (ce-base-source-same $old-size $conjunct $base $same))
        (- (ce-expand-pair $old-size $conjunct $base))
         (- (ce-expand-todo $old-size $conjunct))

             ) )
;; Re-index the sorted candidate by first variable occurrence. Alpha-equivalent
;; Record the candidate's new size.
(DEF ce-candidate-size-fn
   (,(ce-raw-candidate $old-size $raw))
    (O
        (pure
            (ce-candidate-size $old-size $candidate $size)
            $size
            (size-atom (' (vars_to_indices (' 
              (indices_to_vars 
                ('  (sort-atom (' $raw))))
            ))
        )))
 (- (ce-raw-candidate $old-size $raw)))    )



;; Keep only candidates that actually grew and are within depth-of-conjunct.
(DEF ce-candidate-pass-fn
    (, (ce-candidate-size $old-size $candidate $size)
       (ce-max-depth-i32 $max-depth $max-depth-i32))
    (O
        (pure
            (ce-candidate-depth-pass $candidate $size $pass)
            $pass
            (le_i32 (i32_from_string $size) $max-depth-i32))
        (pure
            (ce-candidate-growth-pass $candidate $size $growth-pass)
            $growth-pass
            (gt_i32 (i32_from_string $size) (i32_from_string $old-size)))
        (- (ce-candidate-size $old-size $candidate $size))))
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
(DEF ce-drop-expand-fn
    (, (ce-expand-pass $size $candidate false)
       (ce-support-pass $size $candidate $support false))
    (O
        (- (ce-support-pass $size $candidate $support false))
        (- (ce-expand-pass $size $candidate false)))) 
(DEF ce-drop-candidate-fn
    (, (ce-candidate-depth-pass $candidate $size $depth-pass)
       (ce-candidate-growth-pass $candidate $size $growth-pass))
    (O
        (- (ce-candidate-depth-pass $candidate $size $depth-pass))
        (- (ce-candidate-growth-pass $candidate $size $growth-pass))))

;;===============================================================
;; Pipeline
;;===============================================================

;; Only an existing conjunct variable connects a generated base. Fresh and
;; constant slots carry zero so max_i8 implements the connectivity OR.
(ce-source-connectivity existing 1)
(ce-source-connectivity fresh 0)
(ce-source-connectivity constant 0)

;; Convert threshold and max depth once. The binary values are intentionally
;; opaque in dumps; they are only used by later grounded comparisons.
(exec (CE 0 0)
    (,
       (depth-of-conjunct $max-depth))
    (O
        (pure
            (ce-max-depth-i32 $max-depth $max-depth-i32)
            $max-depth-i32
            (i32_from_string $max-depth))))

;; Accept only triplet-format pattern atoms. Each singleton candidate is queued
;; so the same support/filter/expand machinery handles level 1 and later levels.
(exec (CE 0 1)
    (, (pattern 0 $pattern))
    (O
        (pure
            
            (exec (0 0) (,) (O (+ (ce-base $indexed)) (+ (ce-pending 1 ($indexed)))))
            $indexed
            (vars_to_indices (' $pattern))
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


