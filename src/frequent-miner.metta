(DEF gv-expand
  (, (gv-visit $id $path $node))
  (O
    (- (gv-visit $id $path $node))
    (pure (gv-var-check $id $path $node $is-var) $is-var
      (i8_to_string (is_var (' $node))))

    (+ (exec (freq 030 gv-record)
         (, (gv-var-check $record-id $record-path $var-node 1))
         (O
           (- (gv-var-check $record-id $record-path $var-node 1))
           (+ (get-vars-for-tree-result $record-id $record-path $var-node)))))

    (+ (exec (freq 031 gv-split-pair)
         (, (gv-var-check $split-id $split-path ($a $b) 0)
            (DEF gv-expand $expand-p $expand-t))
         (O
           (- (gv-var-check $split-id $split-path ($a $b) 0))
           (+ (gv-visit $split-id ($split-path arg/0) $a))
           (+ (gv-visit $split-id ($split-path arg/1) $b))
           (+ (exec (freq 020 gv-expand) $expand-p $expand-t)))))

    (+ (exec (freq 032 gv-split-triplet)
         (, (gv-var-check $split-id $split-path ($a $b $c) 0)
            (DEF gv-expand $expand-p $expand-t))
         (O
           (- (gv-var-check $split-id $split-path ($a $b $c) 0))
           (+ (gv-visit $split-id ($split-path arg/0) $a))
           (+ (gv-visit $split-id ($split-path arg/1) $b))
           (+ (gv-visit $split-id ($split-path arg/2) $c))
           (+ (exec (freq 020 gv-expand) $expand-p $expand-t)))))

    (+ (exec (freq 039 gv-discard-non-var)
         (, (gv-var-check $discard-id $discard-path $node 0))
         (O
           (- (gv-var-check $discard-id $discard-path $node 0)))))
  )
)

; Reusable variable-extraction function.
;
; To call it from another miner stage, match/create:
;   (get-vars-for-tree $id $tree)
;   (DEF get-vars-for-tree-fn $gv-p $gv-t)
; then emit:
;   (+ (exec (freq 010 run-get-vars) $gv-p $gv-t))
(DEF get-vars-for-tree-fn
  (, (get-vars-for-tree $id $tree)
     (DEF gv-expand $expand-p $expand-t))
  (O
    (- (get-vars-for-tree $id $tree))
    (pure (gv-visit $id root $indexed-tree) $indexed-tree
      (vars_to_indices (' $tree)))
    (+ (exec (freq 020 gv-expand) $expand-p $expand-t)))
)

; Example call, kept inactive so this file can be loaded as a library:
; (get-vars-for-tree sample (Inheritance $x (Evaluation $x $y)))
; (exec (freq 000 call-get-vars-example)
;   (, (get-vars-for-tree sample (Inheritance $x (Evaluation $x $y)))
;      (DEF get-vars-for-tree-fn $gv-p $gv-t))
;   (O (+ (exec (freq 010 run-get-vars) $gv-p $gv-t))))

; get-value-at-position
;
; Recursive positional lookup. It walks only the requested path:
;   root                      -> the whole expression
;   ($parent arg/0)           -> first child of value at $parent
;   ($parent arg/1)           -> second child of value at $parent
;   ($parent arg/2)           -> third child of value at $parent
;
; Request:
;   (get-value-at-position $id $expr $path)
;
; Result:
;   (get-value-at-position-result $id $path $value)
;
; Internal:
;   (gap-task $id $expr $path)
;   (gap-wait $id $path $parent $arg)
;   (gap-value $id $path $value)

(gap-arg-index arg/0 0)
(gap-arg-index arg/1 1)
(gap-arg-index arg/2 2)

(DEF get-value-at-position-select
  (, (gap-value $id $parent $parent-value))
  (O
    (+ (exec (freq 130 gap-select-by-index)
         (, (gap-wait $sel-id $path $parent $arg)
            (gap-value $sel-id $parent $parent-value)
            (gap-arg-index $arg $index)
            (DEF get-value-at-position-select $select-p $select-t))
         (O
           (- (gap-wait $sel-id $path $parent $arg))
           (- (gap-value $sel-id $parent $parent-value))
           (pure (gap-value $sel-id $path $value) $value
             (index-atom $index (' $parent-value)))
           (+ (exec (freq 120 gap-select) $select-p $select-t)))))

    (+ (exec (freq 190 gap-result)
         (, (gap-value $result-id $result-path $result-value)
            (gap-target $result-id $result-path))
         (O
           (- (gap-target $result-id $result-path))
           (- (gap-value $result-id $result-path $result-value))
           (+ (get-value-at-position-result $result-id $result-path $result-value)))))
  )
)

(DEF get-value-at-position-step
  (, (gap-task $id $expr $path))
  (O
    (+ (exec (freq 110 gap-root)
         (, (gap-task $root-id $expr root)
            (DEF get-value-at-position-select $select-p $select-t))
         (O
           (- (gap-task $root-id $expr root))
           (+ (gap-value $root-id root $expr))
           (+ (exec (freq 120 gap-select) $select-p $select-t)))))

    (+ (exec (freq 111 gap-descend)
         (, (gap-task $desc-id $expr ($parent $arg))
            (DEF get-value-at-position-step $step-p $step-t))
         (O
           (- (gap-task $desc-id $expr ($parent $arg)))
           (+ (gap-wait $desc-id ($parent $arg) $parent $arg))
           (+ (gap-task $desc-id $expr $parent))
           (+ (exec (freq 100 gap-step) $step-p $step-t)))))
  )
)

; Reusable get-value-at-position function.
;
; To call it from another miner stage, match/create:
;   (get-value-at-position $id $expr $path)
;   (DEF get-value-at-position-fn $gap-p $gap-t)
; then emit:
;   (+ (exec (freq 101 run-get-value-at-position) $gap-p $gap-t))
(DEF get-value-at-position-fn
  (, (get-value-at-position $id $expr $path)
     (DEF get-value-at-position-step $step-p $step-t))
  (O
    (- (get-value-at-position $id $expr $path))
    (+ (gap-target $id $path))
    (+ (gap-task $id $expr $path))
    (+ (exec (freq 100 gap-step) $step-p $step-t)))
)
; Example call, kept inactive:
; (get-value-at-position gap-example
;   (Inheritance Allen (Evaluation (Var 1) (like (we sodaDrinker) dean)))
;   (((root arg/2) arg/1) arg/0))
; (exec (freq 000 call-gap-example)
;   (, (get-value-at-position gap-example
;        (Inheritance Allen (Evaluation (Var 1) (like (we sodaDrinker) dean)))
;        (((root arg/2) arg/1) arg/0))
;      (DEF get-value-at-position-fn $gap-p $gap-t))
;   (O (+ (exec (freq 101 run-get-value-at-position) $gap-p $gap-t))))

; valuation
;
; Valuation pipeline:
;   1. Extract variables and their paths from the pattern.
;   2. Match the raw pattern against loaded FACT rows.
;   3. For each satisfying expression and each variable path, get the value at
;      that path.
;   4. Emit variable bindings for the valuation request.
;
; Request:
;   (valuation $id $pattern)
;
; Knowledge base facts:
;   (FACT $expr)
;
; Results:
;   (valuation-satisfying-set $id $candidate-expr)
;   (valuation-binding $id $path $var $value)
;
; Candidate ids are intentionally not part of the valuation result model.

(DEF valuation-start
  (, (valuation $id $pattern))
  (O
    (- (valuation $id $pattern))
    (+ (get-vars-for-tree (VAL-VARS $id) $pattern))
    (+ (valuation-pattern $id $pattern)))
)

(DEF valuation-match
  (, (valuation-pattern $id $pattern)
     (FACT $pattern))
  (O
    (+ (valuation-satisfying-set $id $pattern)))
)

(DEF valuation-bind
  (, (valuation-satisfying-set $id $candidate-expr)
     (get-vars-for-tree-result (VAL-VARS $id) $path $var)
     (DEF get-value-at-position-fn $gap-p $gap-t))
  (O
    (+ (gap-valuation-binding (VAL-VALUE $id $candidate-expr $path)
         $id
         $path
         $var))
    (+ (get-value-at-position (VAL-VALUE $id $candidate-expr $path)
         $candidate-expr
         $path))
    (- (get-vars-for-tree-result (VAL-VARS $id) $path $var))
    (- (valuation-satisfying-set $id $candidate-expr))
    (+ (exec (freq 231 valuation-get-value) $gap-p $gap-t)))
)

(DEF valuation-binding-finish
  (, (gap-valuation-binding (VAL-VALUE $id $candidate-expr $path) $id $path $var)
     (get-value-at-position-result (VAL-VALUE $id $candidate-expr $path) $path $value))
  (O
    (- (gap-valuation-binding (VAL-VALUE $id $candidate-expr $path) $id $path $var))
    (- (get-value-at-position-result (VAL-VALUE $id $candidate-expr $path) $path $value))
    (+ (valuation-binding $id $path $var $value)))
)

; Reusable valuation function.
;
; To call it from another miner stage, match/create:
;   (valuation $id $pattern)
;   (FACT $candidate-expr)
;   (DEF valuation-fn $val-p $val-t)
; then emit:
;   (+ (exec (freq 200 run-valuation) $val-p $val-t))
(DEF valuation-fn
  (, (valuation $id $pattern)
     (DEF valuation-start $start-p $start-t)
     (DEF valuation-match $match-p $match-t)
     (DEF valuation-bind $bind-p $bind-t)
     (DEF valuation-binding-finish $finish-p $finish-t)
     (DEF get-vars-for-tree-fn $gv-p $gv-t))
  (O
    (+ (exec (freq 200 valuation-start) $start-p $start-t))
    (+ (exec (freq 210 valuation-get-vars) $gv-p $gv-t))
    (+ (exec (freq 220 valuation-match) $match-p $match-t))
    (+ (exec (freq 230 valuation-bind) $bind-p $bind-t))
    (+ (exec (freq 240 valuation-finish) $finish-p $finish-t)))
)

; Example call, kept inactive:
; (valuation val-example (Inheritance $x $y))
; (FACT (Inheritance Allen human))
; (FACT (Inheritance Lily human))
; (FACT (Inheritance Allen sodaDrinker))
; (exec (freq 000 call-example)
;   (, (valuation val-example (Inheritance $x human))
;      (DEF valuation-fn $val-p $val-t))
;   (O (+ (exec (freq 001 run-valuation) $val-p $val-t))))
