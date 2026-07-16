(DEF gv-expand
  (, (gv-visit $id $path $node))
  (O
    (- (gv-visit $id $path $node))
    (pure (gv-var-check $id $path $node $is-var) $is-var
      (i8_to_string (is_var (' $node))))

    (+ (exec (GV 3 0 record)
         (, (gv-var-check $record-id $record-path $var-node 1))
         (O
           (- (gv-var-check $record-id $record-path $var-node 1))
           (+ (get-vars-for-tree-result $record-id $record-path $var-node)))))

    (+ (exec (GV 3 1 split-pair)
         (, (gv-var-check $split-id $split-path ($a $b) 0)
            (DEF gv-expand $expand-p $expand-t))
         (O
           (- (gv-var-check $split-id $split-path ($a $b) 0))
           (+ (gv-visit $split-id ($split-path arg/0) $a))
           (+ (gv-visit $split-id ($split-path arg/1) $b))
           (+ (exec (GV 2) $expand-p $expand-t)))))

    (+ (exec (GV 3 1 split-triplet)
         (, (gv-var-check $split-id $split-path ($a $b $c) 0)
            (DEF gv-expand $expand-p $expand-t))
         (O
           (- (gv-var-check $split-id $split-path ($a $b $c) 0))
           (+ (gv-visit $split-id ($split-path arg/0) $a))
           (+ (gv-visit $split-id ($split-path arg/1) $b))
           (+ (gv-visit $split-id ($split-path arg/2) $c))
           (+ (exec (GV 2) $expand-p $expand-t)))))
  )
)

; Reusable variable-extraction function.
;
; To call it from another miner stage, match/create:
;   (get-vars-for-tree $id $tree)
;   (DEF get-vars-for-tree-fn $gv-p $gv-t)
; then emit:
;   (+ (exec (GV 0 run-get-vars) $gv-p $gv-t))
(DEF get-vars-for-tree-fn
  (, (get-vars-for-tree $id $tree)
     (DEF gv-expand $expand-p $expand-t))
  (O
    (pure (gv-visit $id root $indexed-tree) $indexed-tree
      (vars_to_indices (' $tree)))
    (+ (exec (GV 2) $expand-p $expand-t)))
)

; Example call, kept inactive so this file can be loaded as a library:
; (get-vars-for-tree sample (Inheritance $x (Evaluation $x $y)))
; (exec (GV 0 call-example)
;   (, (get-vars-for-tree sample (Inheritance $x (Evaluation $x $y)))
;      (DEF get-vars-for-tree-fn $gv-p $gv-t))
;   (O (+ (exec (GV 0 run-get-vars) $gv-p $gv-t))))

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
    (+ (exec (GAP 3 select-by-index)
         (, (gap-wait $sel-id $path $parent $arg)
            (gap-value $sel-id $parent $parent-value)
            (gap-arg-index $arg $index)
            (DEF get-value-at-position-select $select-p $select-t))
         (O
           (- (gap-wait $sel-id $path $parent $arg))
           (pure (gap-value $sel-id $path $value) $value
             (index-atom $index (' $parent-value)))
           (+ (exec (GAP 0 select) $select-p $select-t)))))

    (+ (exec (GAP 9 result)
         (, (gap-value $result-id $result-path $result-value)
            (gap-target $result-id $result-path))
         (O
           (- (gap-target $result-id $result-path))
           (+ (get-value-at-position-result $result-id $result-path $result-value)))))
  )
)

(DEF get-value-at-position-step
  (, (gap-task $id $expr $path))
  (O
    (+ (exec (GAP 1 root)
         (, (gap-task $root-id $expr root)
            (DEF get-value-at-position-select $select-p $select-t))
         (O
           (- (gap-task $root-id $expr root))
           (+ (gap-value $root-id root $expr))
           (+ (exec (GAP 0 select) $select-p $select-t)))))

    (+ (exec (GAP 2 descend)
         (, (gap-task $desc-id $expr ($parent $arg))
            (DEF get-value-at-position-step $step-p $step-t))
         (O
           (- (gap-task $desc-id $expr ($parent $arg)))
           (+ (gap-wait $desc-id ($parent $arg) $parent $arg))
           (+ (gap-task $desc-id $expr $parent))
           (+ (exec (GAP 0 step) $step-p $step-t)))))
  )
)

; Reusable get-value-at-position function.
;
; To call it from another miner stage, match/create:
;   (get-value-at-position $id $expr $path)
;   (DEF get-value-at-position-fn $gap-p $gap-t)
; then emit:
;   (+ (exec (GAP 0 run-get-value-at-position) $gap-p $gap-t))
(DEF get-value-at-position-fn
  (, (get-value-at-position $id $expr $path)
     (DEF get-value-at-position-step $step-p $step-t))
  (O
    (+ (gap-target $id $path))
    (+ (gap-task $id $expr $path))
    (+ (exec (GAP 0 step) $step-p $step-t)))
)

; Example call, kept inactive:
; (get-value-at-position gap-example
;   (Inheritance Allen (Evaluation (Var 1) (like (we sodaDrinker) dean)))
;   (((root arg/2) arg/1) arg/0))
; (exec (GAP 0 call-example)
;   (, (get-value-at-position gap-example
;        (Inheritance Allen (Evaluation (Var 1) (like (we sodaDrinker) dean)))
;        (((root arg/2) arg/1) arg/0))
;      (DEF get-value-at-position-fn $gap-p $gap-t))
;   (O (+ (exec (GAP 0 run-get-value-at-position) $gap-p $gap-t))))

; valuation
;
; Valuation pipeline:
;   1. Extract variables and their paths from the pattern.
;   2. Match the pattern against a knowledge base.
;   3. For each satisfying expression and each variable path, get the value at
;      that path.
;   4. Emit variable bindings for the satisfying expression.
;
; Request:
;   (valuation $id $kb $pattern)
;
; Knowledge base facts:
;   (knowledge-base $kb $candidate-id $expr)
;
; Results:
;   (valuation-satisfying-set $id $candidate-id $candidate-expr)
;   (valuation-binding $id $candidate-id $path $var $value)

(DEF valuation-start
  (, (valuation $id $kb $pattern))
  (O
    (+ (get-vars-for-tree (VAL-VARS $id) $pattern))
    (+ (valuation-pattern $id $kb $pattern)))
)

(DEF valuation-match
  (, (valuation-pattern $id $kb $pattern)
     (knowledge-base $kb $candidate-id $pattern))
  (O
    (+ (valuation-satisfying-set $id $candidate-id $pattern))
  )
)

(DEF valuation-bind
  (, (valuation-satisfying-set $id $candidate-id $candidate-expr)
     (get-vars-for-tree-result (VAL-VARS $id) $path $var)
     (DEF get-value-at-position-fn $gap-p $gap-t))
  (O
    (+ (gap-valuation-binding (VAL-VALUE $id $candidate-id $path)
         $id
         $candidate-id
         $path
         $var))
    (+ (get-value-at-position (VAL-VALUE $id $candidate-id $path)
         $candidate-expr
         $path))
    (+ (exec (VAL 4 get-value) $gap-p $gap-t)))
)

(DEF valuation-binding-finish
  (, (gap-valuation-binding (VAL-VALUE $id $candidate-id $path)
       $id
       $candidate-id
       $path
       $var)
     (get-value-at-position-result (VAL-VALUE $id $candidate-id $path)
       $path
       $value))
  (O
    (- (gap-valuation-binding (VAL-VALUE $id $candidate-id $path)
         $id
         $candidate-id
         $path
         $var))
    (+ (valuation-binding $id $candidate-id $path $var $value))
    (+ (valuation-binding $id v $path $var $var)))
)

; Reusable valuation function.
;
; To call it from another miner stage, match/create:
;   (valuation $id $kb $pattern)
;   (knowledge-base $kb $candidate-id $candidate-expr)
;   (DEF valuation-fn $val-p $val-t)
; then emit:
;   (+ (exec (VAL 0 run-valuation) $val-p $val-t))
(DEF valuation-fn
  (, (valuation $id $kb $pattern)
     (DEF valuation-start $start-p $start-t)
     (DEF valuation-match $match-p $match-t)
     (DEF valuation-bind $bind-p $bind-t)
     (DEF valuation-binding-finish $finish-p $finish-t)
     (DEF get-vars-for-tree-fn $gv-p $gv-t))
  (O
    (+ (exec (VAL 0 start) $start-p $start-t))
    (+ (exec (VAL 1 get-vars) $gv-p $gv-t))
    (+ (exec (VAL 2 match) $match-p $match-t))
    (+ (exec (GV 9 0 valuation-bind-after-get-vars) $bind-p $bind-t))
    (+ (exec (GAP 9 0 valuation-finish-after-get-value) $finish-p $finish-t)))
)

; Example call, kept inactive:
; (valuation val-example kb-example (Inheritance $x human))
; (knowledge-base kb-example c1 (Inheritance Allen human))
; (knowledge-base kb-example c2 (Inheritance Lily human))
; (knowledge-base kb-example c3 (Inheritance Allen sodaDrinker))
; (exec (VAL 0 call-example)
;   (, (valuation val-example kb-example (Inheritance $x human))
;      (DEF valuation-fn $val-p $val-t))
;   (O (+ (exec (VAL 0 run-valuation) $val-p $val-t))))


; shallow abstraction for valuation bindings
;
; This is intentionally shallow:
;   - symbols/atoms stay unchanged
;   - variables stay unchanged
;   - pair/triplet expressions keep their link unchanged
;   - only direct arguments are replaced by split variables
;
; Example:
;   (valuation-binding $id $candidate $path (var 0) (Eval Allen soda))
; becomes:
;   (shallow-abstraction-binding $id $candidate $path (var 0)
;      (Eval (var (0 1)) (var (0 2))))
;
; Nested expression arguments are treated as one shallow child for now.

(DEF shallow-abstraction-start
  (, (run-shallow-abstraction $id) (valuation-binding $id $candidate-id $path (var $source-index) $value))
  (O (pure (shallow-abstraction-request $id $candidate-id $path (var $source-index) $value $is-var)
       $is-var (i8_to_string (is_var (' $value))))))

(DEF shallow-abstraction-step
  (, (shallow-abstraction-request $id $candidate-id $path (var $source-index) $value $is-var))
  (O
    (+ (exec (ABS 2 keep-var)
         (, (shallow-abstraction-request $keep-id $keep-candidate-id $keep-path (var $keep-source-index) $keep-value 1))
         (O (- (shallow-abstraction-request $keep-id $keep-candidate-id $keep-path (var $keep-source-index) $keep-value 1))
            (+ (shallow-abstraction-binding $keep-id $keep-candidate-id $keep-path (var $keep-source-index) $keep-value)))))
    (+ (exec (ABS 3 split-pair)
         (, (shallow-abstraction-request $pair-id $pair-candidate-id $pair-path (var $pair-source-index) ($link $a) 0))
         (O (- (shallow-abstraction-request $pair-id $pair-candidate-id $pair-path (var $pair-source-index) ($link $a) 0))
            (+ (shallow-abstraction-binding $pair-id $pair-candidate-id $pair-path (var $pair-source-index)
                 ($link (var ($pair-source-index 1))))))))
    (+ (exec (ABS 3 split-triplet-same-args)
         (, (shallow-abstraction-request $same-id $same-candidate-id $same-path (var $same-source-index) ($link $a $a) 0))
         (O (- (shallow-abstraction-request $same-id $same-candidate-id $same-path (var $same-source-index) ($link $a $a) 0))
            (+ (shallow-abstraction-binding $same-id $same-candidate-id $same-path (var $same-source-index)
                 ($link (var ($same-source-index 1)) (var ($same-source-index 1))))))))
    (+ (exec (ABS 4 split-triplet)
         (, (shallow-abstraction-request $triplet-id $triplet-candidate-id $triplet-path (var $triplet-source-index) ($link $a $b) 0))
         (O (- (shallow-abstraction-request $triplet-id $triplet-candidate-id $triplet-path (var $triplet-source-index) ($link $a $b) 0))
            (+ (shallow-abstraction-binding $triplet-id $triplet-candidate-id $triplet-path (var $triplet-source-index)
                 ($link (var ($triplet-source-index 1)) (var ($triplet-source-index 2))))))))
    (+ (exec (ABS 9 keep-atom)
         (, (shallow-abstraction-request $atom-id $atom-candidate-id $atom-path (var $atom-source-index) $atom-value 0))
         (O (- (shallow-abstraction-request $atom-id $atom-candidate-id $atom-path (var $atom-source-index) $atom-value 0))
            (+ (shallow-abstraction-binding $atom-id $atom-candidate-id $atom-path (var $atom-source-index) $atom-value)))))))

(DEF shallow-abstraction-fn
  (, (run-shallow-abstraction $id) (DEF shallow-abstraction-start $start-p $start-t) (DEF shallow-abstraction-step $step-p $step-t))
  (O (+ (exec (ABS 0 start) $start-p $start-t)) (+ (exec (ABS 1 step) $step-p $step-t))))

; shallow expression abstraction primitives
;
; This is the small reusable core for the next abstraction pass:
;   1. split an expression into link + args using car-atom/cdr-atom
;   2. collect abstracted args with append
;   3. reuse split variables from per-expression history when values repeat
;   4. keep the original link available for the rebuild stage
;
; Request:
;   (sae-rebuild-smoke $id $expr $reversed-abstracted-args)
;
; Result:
;   (sae-rebuild-smoke-result $id $rebuilt)
; shallow abstract expression
;
; Request:
;   (shallow-abstract-expression $id (var $source-index) $expr)
;
; Result:
;   (shallow-abstract-expression-result $id $abstracted-expr)
;
; The helper walks the direct args of $expr, keeps the link unchanged, stores
; value -> split-var history in atomspace, and collects output with append.
(sae-index-next 1 2)
(sae-index-next 2 3)
(sae-index-next 3 4)
(sae-index-next 4 5)
(sae-index-next 5 6)
(sae-index-next 6 7)
(sae-index-next 7 8)
(sae-index-next 8 9)

(DEF sae-start
  (, (shallow-abstract-expression $id (var $source-index) $expr))
  (O
    (pure (sae-link $id $link) $link (car-atom (' $expr)))
    (pure (sae-args $id (var $source-index) $args) $args (cdr-atom (' $expr)))))

(DEF sae-start-walk
  (, (sae-args $id (var $source-index) $args))
  (O
    (+ (sae-walk $id (var $source-index) $args 1 ()))))

(DEF sae-step
  (, (sae-walk $id (var $source-index) $args $pos $acc)
     (sae-index-next $pos $next-pos)
     (DEF sae-history-resolve $hist-p $hist-t))
  (O
    (pure (sae-current $id $pos $value) $value (car-atom (' $args)))
    (pure (sae-step-rest $id (var $source-index) $pos $rest) $rest (cdr-atom (' $args)))
    (- (sae-walk $id (var $source-index) $args $pos $acc))
    (+ (sae-history-pending $id (var $source-index) $pos $next-pos $acc))
    (+ (exec (SAE 4 resolve-history) $hist-p $hist-t))))

(DEF sae-history-resolve
  (, (sae-history-pending $id (var $source-index) $pos $next-pos $acc)
     (sae-current $id $pos $value)
     (sae-step-rest $id (var $source-index) $pos $rest)
     (DEF sae-continue $cont-p $cont-t))
  (O
    (+ (exec (SAE 4 0 reuse-history)
         (, (sae-history-pending $reuse-id (var $reuse-source-index) $reuse-pos $reuse-next-pos $reuse-acc)
            (sae-current $reuse-id $reuse-pos $reuse-value)
            (sae-step-rest $reuse-id (var $reuse-source-index) $reuse-pos $reuse-rest)
            (sae-pos-history $reuse-id (var $reuse-source-index) $reuse-value $first-pos))
         (O
           (- (sae-history-pending $reuse-id (var $reuse-source-index) $reuse-pos $reuse-next-pos $reuse-acc))
           (pure (sae-step-acc $reuse-id (var $reuse-source-index) $reuse-next-pos $reuse-next-acc) $reuse-next-acc
             (append (' ($reuse-acc ((var ($reuse-source-index $first-pos)))))))
           (+ (exec (SAE 5 continue-walk) $cont-p $cont-t)))))
    (+ (exec (SAE 4 1 new-history)
         (, (sae-history-pending $new-id (var $new-source-index) $new-pos $new-next-pos $new-acc)
            (sae-current $new-id $new-pos $new-value)
            (sae-step-rest $new-id (var $new-source-index) $new-pos $new-rest))
         (O
           (- (sae-history-pending $new-id (var $new-source-index) $new-pos $new-next-pos $new-acc))
           (+ (sae-pos-history $new-id (var $new-source-index) $new-value $new-pos))
           (pure (sae-step-acc $new-id (var $new-source-index) $new-next-pos $new-next-acc) $new-next-acc
             (append (' ($new-acc ((var ($new-source-index $new-pos)))))))
           (+ (exec (SAE 5 continue-walk) $cont-p $cont-t)))))))

(DEF sae-continue
  (, (sae-step-rest $id (var $source-index) $pos $rest)
     (sae-step-acc $id (var $source-index) $next-pos $next-acc)
     (DEF sae-finish $finish-p $finish-t)
     (DEF sae-step $step-p $step-t))
  (O
    (- (sae-step-rest $id (var $source-index) $pos $rest))
    (- (sae-step-acc $id (var $source-index) $next-pos $next-acc))
    (+ (sae-walk $id (var $source-index) $rest $next-pos $next-acc))
    (+ (exec (SAE 5 finish-walk) $finish-p $finish-t))
    (+ (exec (SAE 6 step-new-node) $step-p $step-t))))

(DEF sae-finish
  (, (sae-walk $id (var $source-index) () $pos $acc)
     (sae-link $id $link)
     (sae-current $rid $rpos $rvalue)
     (sae-pos-history $rid $rs-index $rvalue $rfirst-pos))
  (O
    (- (sae-walk $id (var $source-index) () $pos $acc))
    (- (sae-link $id $link))
    (- (sae-current $rid $rpos $rvalue))
    (- (sae-pos-history $rid $rs-index $rvalue $rfirst-pos))
    (pure (sae-step-result $id (var $source-index) $res) $res (append (' (($link) $acc))))))

(DEF shallow-abstract-expression-fn
  (, (shallow-abstract-expression $id (var $source-index) $expr)
     (DEF sae-start $start-p $start-t)
     (DEF sae-start-walk $walk-p $walk-t)
     (DEF sae-step $step-p $step-t))
  (O
    (+ (exec (SAE 1 start-expression) $start-p $start-t))
    (+ (exec (SAE 2 start-walk) $walk-p $walk-t))
    (+ (exec (SAE 3 step-new-node) $step-p $step-t))))

(shallow-abstract-expression expr-smoke (var 0) (Eval Allen Allen Allenc lili Allenc hi))
(exec (SAE 0 call-expr)
  (, (shallow-abstract-expression expr-smoke (var 0) (Eval Allen Allen Allenc lili Allenc hi))
     (DEF shallow-abstract-expression-fn $p $t))
  (O (+ (exec (SAE 0 run-expr) $p $t))))

