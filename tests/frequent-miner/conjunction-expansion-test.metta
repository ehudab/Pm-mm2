;; TEST-AUX data/ugly-sodaDrinker.metta
;; TEST-AUX src/common-utils/utils.metta
;; TEST-AUX src/frequent-miner.metta

(INPUT DB db)
(INPUT MIN-SUPPORT 2)
(INPUT MAX-SIZE 3)

(pattern 0 (Inheritance $x $y))
(pattern 0 (Inheritance $x human))
(pattern 0 (Inheritance $x ugly))
(pattern 0 (Inheritance $x sodaDrinker))

;; Constant-slot expansion.
(EXPECTED-RESULT constant-singleton (frequent-pattern (, (Inheritance $a human)) 19))
(EXPECTED-RESULT constant-size-2 (frequent-pattern (, (Inheritance $a ugly) (Inheritance $a sodaDrinker)) 5))
(EXPECTED-RESULT constant-size-3 (frequent-pattern (, (Inheritance $a ugly) (Inheritance $a human) (Inheritance $a sodaDrinker)) 4))

;; Distinct-variable connected expansion and canonicalization.
(EXPECTED-RESULT canonical-fan (frequent-pattern (, (Inheritance $a $b) (Inheritance $a $c)) 183))
(EXPECTED-RESULT canonical-join (frequent-pattern (, (Inheritance $a $b) (Inheritance $c $b)) 761))
