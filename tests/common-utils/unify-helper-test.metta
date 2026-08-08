;; TEST-AUX src/common-utils/utils.metta

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; MM2 helper `unify` behavior
;;
;; Direct form works well for simple symbol operands:
;;
;;   (unify a a matched failed)
;;
;; For expression operands, use the tuple form so each expression is preserved
;; as one helper argument:
;;
;;   (unify (' ($left $right matched failed)))
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(exec 0
    (, (run-unify-helper-tests))
    (O
        (pure
            (unify-helper-result symbol-match $out)
            $out
            (unify a a matched failed))
        (pure
            (unify-helper-result variable-match $out)
            $out
            (unify (' ((Inheritance $x man) (Inheritance Bob man) matched failed))))
        (pure
            (unify-helper-result nested-match $out)
            $out
            (unify (' ((Evaluation (PredicateNode likes) ($x pizza)) (Evaluation (PredicateNode likes) (Bob pizza)) matched failed))))
        (pure
            (unify-helper-result constant-mismatch $out)
            $out
            (unify (' ((Inheritance Bob man) (Inheritance Bob ugly) matched failed))))))

(run-unify-helper-tests)

(EXPECTED-RESULT symbol-match (unify-helper-result symbol-match matched))

(EXPECTED-RESULT variable-match (unify-helper-result variable-match matched))

(EXPECTED-RESULT nested-match (unify-helper-result nested-match matched))

(EXPECTED-RESULT constant-mismatch (unify-helper-result constant-mismatch failed))
