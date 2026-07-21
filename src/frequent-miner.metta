;; Frequent-pattern miner for triplet atoms.
;;
;; Public inputs:
;;   (INPUT MIN-SUPPORT n)
;;   (INPUT MAX-SIZE n)
;;   (pattern 0 ($predicate $left $right))
;;
;; Public output:
;;   (frequent-pattern (, ...conjuncts...) support)

;; Count a queued candidate, then install the later stages needed by the same
;; cycle. The schedulers keep substituted DEF bodies below MORK's 64-variable
;; limit.
(DEF freq-support-fn
  (, (freq-pending $size $candidate)
     (DEF freq-schedule-filter-fn $filter-p $filter-t)
     (DEF freq-schedule-depth-fn $depth-p $depth-t)
     (DEF freq-build-fn $build-p $build-t)
     (DEF freq-schedule-candidate-fn $candidate-p $candidate-t))
  (O
    (- (freq-pending $size $candidate))
    (pure
      (exec (freq 110 count-support)
        $query
        (O (count (freq-support $size $candidate $support) $support $query)))
      $query
      (indices_to_vars (cons , (' $candidate))))
    (+ (exec (freq 120 schedule-filter) $filter-p $filter-t))
    (+ (exec (freq 200 schedule-depth) $depth-p $depth-t))
    (+ (exec (freq 300 schedule-build) $build-p $build-t))
    (+ (exec (freq 500 schedule-candidate) $candidate-p $candidate-t))))

;; Support filtering.
(DEF freq-schedule-filter-fn
  (, (freq-support $size $candidate $support)
     (DEF freq-support-pass-fn $pass-p $pass-t)
     (DEF freq-save-pass-fn $save-p $save-t)
     (DEF freq-drop-fail-fn $drop-p $drop-t))
  (O
    (+ (exec (freq 130 check-support) $pass-p $pass-t))
    (+ (exec (freq 140 save-frequent) $save-p $save-t))
    (+ (exec (freq 141 drop-infrequent) $drop-p $drop-t))))

(DEF freq-support-pass-fn
  (, (freq-support $size $candidate $support)
     (INPUT MIN-SUPPORT $threshold))
  (O
    (pure
      (freq-support-pass $size $candidate $support $pass)
      $pass
      (ge_i32 (i32_from_string $support) (i32_from_string $threshold)))
    (- (freq-support $size $candidate $support))))

(DEF freq-save-pass-fn
  (, (freq-support-pass $size $candidate $support true))
  (O
    (pure
      (frequent-pattern $pattern $support)
      $pattern
      (indices_to_vars (cons , (' $candidate))))
    (+ (freq-expand-check $size $candidate))
    (- (freq-support-pass $size $candidate $support true))))

(DEF freq-drop-fail-fn
  (, (freq-support-pass $size $candidate $support false))
  (O (- (freq-support-pass $size $candidate $support false))))

;; Only frequent candidates below MAX-SIZE are expanded.
(DEF freq-schedule-depth-fn
  (, (freq-expand-check $size $candidate)
     (DEF freq-expand-pass-fn $pass-p $pass-t)
     (DEF freq-expand-todo-fn $todo-p $todo-t)
     (DEF freq-drop-expand-fn $drop-p $drop-t))
  (O
    (+ (exec (freq 210 check-depth) $pass-p $pass-t))
    (+ (exec (freq 220 queue-expansion) $todo-p $todo-t))
    (+ (exec (freq 221 stop-expansion) $drop-p $drop-t))))

(DEF freq-expand-pass-fn
  (, (freq-expand-check $size $candidate)
     (INPUT MAX-SIZE $max-size))
  (O
    (pure
      (freq-expand-pass $size $candidate $pass)
      $pass
      (lt_i32 (i32_from_string $size) (i32_from_string $max-size)))
    (- (freq-expand-check $size $candidate))))

(DEF freq-expand-todo-fn
  (, (freq-expand-pass $size $candidate true))
  (O
    (+ (freq-expand-todo $size $candidate))
    (- (freq-expand-pass $size $candidate true))))

(DEF freq-drop-expand-fn
  (, (freq-expand-pass $size $candidate false))
  (O (- (freq-expand-pass $size $candidate false))))

;; Candidate construction is split into small schedulers because inlining all
;; DEF bodies into one rule exceeds MORK's variable limit.
(DEF freq-build-fn
  (, (freq-expand-todo $old-size $conjunct)
     (DEF freq-schedule-scan-fn $scan-p $scan-t)
     (DEF freq-schedule-classify-fn $classify-p $classify-t)
     (DEF freq-schedule-choice-fn $choice-p $choice-t)
     (DEF freq-schedule-map-fn $map-p $map-t))
  (O
    (+ (exec (freq 310 schedule-scan) $scan-p $scan-t))
    (+ (exec (freq 350 schedule-classify) $classify-p $classify-t))
    (+ (exec (freq 370 schedule-choice) $choice-p $choice-t))
    (+ (exec (freq 400 schedule-map) $map-p $map-t))))

;; Pair each expandable conjunction with every normalized base, start its
;; shape classification, and scan the conjunction's atoms.
(DEF freq-schedule-scan-fn
  (, (freq-expand-todo $old-size $conjunct)
     (DEF freq-expand-pair-fn $pair-p $pair-t)
     (DEF freq-pair-details-fn $details-p $details-t)
     (DEF freq-scan-fn $scan-p $scan-t))
  (O
    (+ (exec (freq 320 pair-base) $pair-p $pair-t))
    (+ (exec (freq 330 inspect-pair) $details-p $details-t))
    (+ (exec (freq 340 scan-conjunct) $scan-p $scan-t))))

(DEF freq-expand-pair-fn
  (, (freq-expand-todo $old-size $conjunct)
     (freq-base $base))
  (O (+ (freq-expand-pair $old-size $conjunct $base))))

(DEF freq-pair-details-fn
  (, (freq-expand-todo $old-size $conjunct)
     (freq-expand-pair $old-size $conjunct
       ($predicate $base-left $base-right)))
  (O
    (+ (freq-scan $old-size $conjunct
      ($predicate $base-left $base-right) $conjunct))
    (pure
      (freq-base-shape-left $old-size $conjunct
        ($predicate $base-left $base-right) $is-var)
      $is-var
      (i8_to_string (is_var (' $base-left))))
    (- (freq-expand-pair $old-size $conjunct
      ($predicate $base-left $base-right)))))

(DEF freq-scan-fn
  (, (freq-expand-todo $old-size $conjunct)
     (freq-scan $old-size $conjunct $base $remaining)
     (DEF freq-scan-fn $scan-p $scan-t))
  (O
    (pure
      (freq-conjunct-atom $old-size $conjunct $base $atom)
      $atom
      (car-atom (' $remaining)))
    (pure
      (freq-scan $old-size $conjunct $base $rest)
      $rest
      (cdr-atom (' $remaining)))
    (- (freq-scan $old-size $conjunct $base $remaining))
    (+ (exec (freq 340 scan-conjunct) $scan-p $scan-t))))

;; Indexed variables in either triplet slot become existing choices. Facts are
;; removed only after both slot rules have seen them.
(DEF freq-schedule-classify-fn
  (, (freq-expand-todo $old-size $conjunct)
     (DEF freq-left-choice-fn $left-p $left-t)
     (DEF freq-right-choice-fn $right-p $right-t)
     (DEF freq-complete-base-shape-fn $shape-p $shape-t)
     (DEF freq-drop-atom-fn $drop-p $drop-t))
  (O
    (+ (exec (freq 351 left-choice) $left-p $left-t))
    (+ (exec (freq 352 right-choice) $right-p $right-t))
    (+ (exec (freq 353 complete-base-shape) $shape-p $shape-t))
    (+ (exec (freq 354 drop-scanned-atom) $drop-p $drop-t))))

(DEF freq-left-choice-fn
  (, (freq-expand-todo $old-size $conjunct)
     (freq-conjunct-atom $old-size $conjunct $base
       ($predicate (var $index) $right)))
  (O
    (+ (freq-cleanup
      (freq-var-choice $old-size $conjunct $base (var $index) existing)))))

(DEF freq-right-choice-fn
  (, (freq-expand-todo $old-size $conjunct)
     (freq-conjunct-atom $old-size $conjunct $base
       ($predicate $left (var $index))))
  (O
    (+ (freq-cleanup
      (freq-var-choice $old-size $conjunct $base (var $index) existing)))))

(DEF freq-complete-base-shape-fn
  (, (freq-expand-todo $old-size $conjunct)
     (freq-base-shape-left $old-size $conjunct
       ($predicate $base-left $base-right) $left-is-var))
  (O
    (pure
      (freq-cleanup
        (freq-base-shape $old-size $conjunct
          ($predicate $base-left $base-right) $left-is-var $right-is-var))
      $right-is-var
      (i8_to_string (is_var (' $base-right))))
    (- (freq-base-shape-left $old-size $conjunct
      ($predicate $base-left $base-right) $left-is-var))))

(DEF freq-drop-atom-fn
  (, (freq-expand-todo $old-size $conjunct)
     (freq-conjunct-atom $old-size $conjunct $base $atom))
  (O (- (freq-conjunct-atom $old-size $conjunct $base $atom))))

;; Contiguous variable indices make max+1 available by proposing every
;; existing successor and deleting proposals that are already existing.
(DEF freq-schedule-choice-fn
  (, (freq-expand-todo $old-size $conjunct)
     (DEF freq-fresh-candidate-fn $fresh-p $fresh-t)
     (DEF freq-drop-used-fresh-fn $drop-p $drop-t)
     (DEF freq-save-fresh-fn $save-p $save-t)
     (DEF freq-source-relation-fn $relation-p $relation-t))
  (O
    (+ (exec (freq 371 propose-fresh) $fresh-p $fresh-t))
    (+ (exec (freq 372 drop-used-fresh) $drop-p $drop-t))
    (+ (exec (freq 373 save-fresh) $save-p $save-t))
    (+ (exec (freq 374 source-relation) $relation-p $relation-t))))

(DEF freq-fresh-candidate-fn
  (, (freq-expand-todo $old-size $conjunct)
     (freq-cleanup
       (freq-var-choice $old-size $conjunct $base (var $index) existing)))
  (O
    (pure
      (freq-fresh-candidate $old-size $conjunct $base (var $next))
      $next
      (i32_to_string (sum_i32 (i32_from_string $index) (i32_one))))))

(DEF freq-drop-used-fresh-fn
  (, (freq-expand-todo $old-size $conjunct)
     (freq-fresh-candidate $old-size $conjunct $base $candidate)
     (freq-cleanup
       (freq-var-choice $old-size $conjunct $base $candidate existing)))
  (O (- (freq-fresh-candidate $old-size $conjunct $base $candidate))))

(DEF freq-save-fresh-fn
  (, (freq-expand-todo $old-size $conjunct)
     (freq-fresh-candidate $old-size $conjunct $base $fresh))
  (O
    (+ (freq-cleanup
      (freq-var-choice $old-size $conjunct $base $fresh fresh)))
    (- (freq-fresh-candidate $old-size $conjunct $base $fresh))))

;; Repeated source variables must remain equal after mapping.
(DEF freq-source-relation-fn
  (, (freq-expand-todo $old-size $conjunct)
     (freq-cleanup
       (freq-base-shape $old-size $conjunct
         ($predicate (var $left) (var $right)) 1 1)))
  (O
    (pure
      (freq-cleanup (freq-source-same $old-size $conjunct
        ($predicate (var $left) (var $right)) $same))
      $same
      (eq_i32 (i32_from_string $left) (i32_from_string $right)))))

;; Generate only connected mappings. This avoids the previous truth table,
;; connectivity facts, pass/drop rules, and disconnected intermediates.
(DEF freq-schedule-map-fn
  (, (freq-expand-todo $old-size $conjunct)
     (DEF freq-map-same-fn $same-p $same-t)
     (DEF freq-map-distinct-left-fn $left-p $left-t)
     (DEF freq-map-distinct-right-fn $right-p $right-t)
     (DEF freq-map-left-slot-fn $left-slot-p $left-slot-t)
     (DEF freq-map-right-slot-fn $right-slot-p $right-slot-t)
     (DEF freq-build-candidate-fn $candidate-p $candidate-t)
     (DEF freq-clean-fn $clean-p $clean-t)
     (DEF freq-finish-build-fn $finish-p $finish-t))
  (O
    (+ (exec (freq 410 map-same-source) $same-p $same-t))
    (+ (exec (freq 411 map-distinct-left) $left-p $left-t))
    (+ (exec (freq 412 map-distinct-right) $right-p $right-t))
    (+ (exec (freq 413 map-left-slot) $left-slot-p $left-slot-t))
    (+ (exec (freq 414 map-right-slot) $right-slot-p $right-slot-t))
    (+ (exec (freq 420 build-candidate) $candidate-p $candidate-t))
    (+ (exec (freq 430 cleanup-build) $clean-p $clean-t))
    (+ (exec (freq 431 finish-build) $finish-p $finish-t))))

(DEF freq-map-same-fn
  (, (freq-expand-todo $old-size $conjunct)
     (freq-cleanup (freq-source-same $old-size $conjunct
       ($predicate $source-left $source-right) true))
     (freq-cleanup (freq-var-choice $old-size $conjunct
       ($predicate $source-left $source-right) $out existing)))
  (O (+ (freq-connected-base $old-size $conjunct
    ($predicate $out $out)))))

;; For different source variables, left-existing/right-any and
;; left-fresh/right-existing are disjoint and cover every connected mapping.
(DEF freq-map-distinct-left-fn
  (, (freq-expand-todo $old-size $conjunct)
     (freq-cleanup (freq-source-same $old-size $conjunct
       ($predicate $source-left $source-right) false))
     (freq-cleanup (freq-var-choice $old-size $conjunct
       ($predicate $source-left $source-right) $left-out existing))
     (freq-cleanup (freq-var-choice $old-size $conjunct
       ($predicate $source-left $source-right) $right-out $right-kind)))
  (O (+ (freq-connected-base $old-size $conjunct
    ($predicate $left-out $right-out)))))

(DEF freq-map-distinct-right-fn
  (, (freq-expand-todo $old-size $conjunct)
     (freq-cleanup (freq-source-same $old-size $conjunct
       ($predicate $source-left $source-right) false))
     (freq-cleanup (freq-var-choice $old-size $conjunct
       ($predicate $source-left $source-right) $left-out fresh))
     (freq-cleanup (freq-var-choice $old-size $conjunct
       ($predicate $source-left $source-right) $right-out existing)))
  (O (+ (freq-connected-base $old-size $conjunct
    ($predicate $left-out $right-out)))))

(DEF freq-map-left-slot-fn
  (, (freq-expand-todo $old-size $conjunct)
     (freq-cleanup (freq-base-shape $old-size $conjunct
       ($predicate $source $constant) 1 0))
     (freq-cleanup (freq-var-choice $old-size $conjunct
       ($predicate $source $constant) $out existing)))
  (O (+ (freq-connected-base $old-size $conjunct
    ($predicate $out $constant)))))

(DEF freq-map-right-slot-fn
  (, (freq-expand-todo $old-size $conjunct)
     (freq-cleanup (freq-base-shape $old-size $conjunct
       ($predicate $constant $source) 0 1))
     (freq-cleanup (freq-var-choice $old-size $conjunct
       ($predicate $constant $source) $out existing)))
  (O (+ (freq-connected-base $old-size $conjunct
    ($predicate $constant $out)))))

;; Build the raw union. Canonicalization uses separate grounded calls because
;; quoted list results cannot safely be piped through nested MM2 calls.
(DEF freq-build-candidate-fn
  (, (freq-expand-todo $old-size $conjunct)
     (freq-connected-base $old-size $conjunct $base))
  (O
    (pure
      (freq-raw-candidate $old-size $raw)
      $raw
      (union-atom (' (($base) $conjunct))))
    (- (freq-connected-base $old-size $conjunct $base))))

;; Durable build state lives once inside a cleanup wrapper. Mapping rules read
;; the nested state directly, then one generic rule removes each wrapper.
(DEF freq-clean-fn
  (, (freq-cleanup $fact))
  (O (- (freq-cleanup $fact))))

(DEF freq-finish-build-fn
  (, (freq-expand-todo $old-size $conjunct))
  (O (- (freq-expand-todo $old-size $conjunct))))

;; Reject duplicate/non-growing or oversized candidates, then start the next
;; support cycle for every candidate that passed.
(DEF freq-schedule-candidate-fn
  (, (freq-raw-candidate $old-size $raw)
     (DEF freq-sort-candidate-fn $sort-p $sort-t)
     (DEF freq-candidate-to-vars-fn $vars-p $vars-t)
     (DEF freq-alpha-candidate-fn $alpha-p $alpha-t)
     (DEF freq-candidate-size-fn $size-p $size-t)
     (DEF freq-candidate-pass-fn $pass-p $pass-t)
     (DEF freq-queue-candidate-fn $queue-p $queue-t)
     (DEF freq-drop-candidate-fn $drop-p $drop-t))
  (O
    (+ (exec (freq 501 sort-candidate) $sort-p $sort-t))
    (+ (exec (freq 502 candidate-to-vars) $vars-p $vars-t))
    (+ (exec (freq 503 alpha-normalize) $alpha-p $alpha-t))
    (+ (exec (freq 510 candidate-size) $size-p $size-t))
    (+ (exec (freq 520 check-candidate) $pass-p $pass-t))
    (+ (exec (freq 530 queue-candidate) $queue-p $queue-t))
    (+ (exec (freq 531 drop-candidate) $drop-p $drop-t))))

(DEF freq-sort-candidate-fn
  (, (freq-raw-candidate $old-size $raw))
  (O
    (pure
      (freq-sorted-candidate $old-size $sorted)
      $sorted
      (sort-atom (' $raw)))
    (- (freq-raw-candidate $old-size $raw))))

(DEF freq-candidate-to-vars-fn
  (, (freq-sorted-candidate $old-size $sorted))
  (O
    (pure
      (freq-candidate-vars $old-size $as-vars)
      $as-vars
      (indices_to_vars (' $sorted)))
    (- (freq-sorted-candidate $old-size $sorted))))

(DEF freq-alpha-candidate-fn
  (, (freq-candidate-vars $old-size $as-vars))
  (O
    (pure
      (freq-candidate $old-size $candidate)
      $candidate
      (vars_to_indices (' $as-vars)))
    (- (freq-candidate-vars $old-size $as-vars))))

(DEF freq-candidate-size-fn
  (, (freq-candidate $old-size $candidate))
  (O
    (pure
      (freq-candidate-size $old-size $candidate $size)
      $size
      (size-atom (' $candidate)))
    (- (freq-candidate $old-size $candidate))))

(DEF freq-candidate-pass-fn
  (, (freq-candidate-size $old-size $candidate $size)
     (INPUT MAX-SIZE $max-size))
  (O
    (pure
      (freq-candidate-pass $candidate $size $pass)
      $pass
      (and_bool
        (le_i32 (i32_from_string $size) (i32_from_string $max-size))
        (gt_i32 (i32_from_string $size) (i32_from_string $old-size))))
    (- (freq-candidate-size $old-size $candidate $size))))

(DEF freq-queue-candidate-fn
  (, (freq-candidate-pass $candidate $size true)
     (DEF freq-support-fn $support-p $support-t))
  (O
    (+ (freq-pending $size $candidate))
    (+ (exec (freq 100 support-cycle) $support-p $support-t))
    (- (freq-candidate-pass $candidate $size true))))

(DEF freq-drop-candidate-fn
  (, (freq-candidate-pass $candidate $size false))
  (O (- (freq-candidate-pass $candidate $size false))))

;; Normalize all seed patterns before starting the first support cycle.
(exec (freq 010 normalize-seeds)
  (, (pattern 0 $pattern))
  (O
    (pure
      (freq-base $base)
      $base
      (vars_to_indices (' $pattern)))
    (pure
      (freq-pending 1 ($base))
      $base
      (vars_to_indices (' $pattern)))))

(exec (freq 020 start)
  (, (DEF freq-support-fn $support-p $support-t))
  (O (+ (exec (freq 100 support-cycle) $support-p $support-t))))

;; Bases are derived input, not output. Priority 900 runs only after all
;; recursively queued mining cycles have finished.
(exec (freq 900 cleanup-bases)
  (, (freq-base $base))
  (O (- (freq-base $base))))
