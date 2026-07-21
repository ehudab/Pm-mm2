;; TEST-AUX data/frequent-miner/conjunction-expansion.metta
;; TEST-AUX src/frequent-miner.metta

(INPUT DB db)
(INPUT MIN-SUPPORT 2)
(INPUT MAX-SIZE 3)

(pattern 0 (Inheritance $x $y))
(pattern 0 (Inheritance $x human))
(pattern 0 (Inheritance $x ugly))
(pattern 0 (Inheritance $x sodaDrinker))
(pattern 0 (Parent $x $y))
(pattern 0 (Knows $x $x))
(pattern 0 (Knows $x $y))

;; Constant-slot expansion.
(EXPECTED-RESULT constant-singleton (frequent-pattern (, (Inheritance $a human)) 4))
(EXPECTED-RESULT constant-size-2 (frequent-pattern (, (Inheritance $a ugly) (Inheritance $a sodaDrinker)) 2))
(EXPECTED-RESULT constant-size-3 (frequent-pattern (, (Inheritance $a ugly) (Inheritance $a human) (Inheritance $a sodaDrinker)) 2))

;; Distinct-variable connected expansion.
(EXPECTED-RESULT chain-singleton (frequent-pattern (, (Parent $a $b)) 6))
(EXPECTED-RESULT chain-size-2 (frequent-pattern (, (Parent $a $b) (Parent $b $c)) 4))
(EXPECTED-RESULT chain-size-3 (frequent-pattern (, (Parent $a $b) (Parent $b $c) (Parent $c $d)) 2))

;; Repeated-variable preservation.
(EXPECTED-RESULT repeated-singleton (frequent-pattern (, (Knows $a $a)) 2))
(EXPECTED-RESULT repeated-size-2 (frequent-pattern (, (Knows $a $a) (Knows $a $b)) 3))

;; Canonical results retained from the original demo.
(EXPECTED-RESULT canonical-fan (frequent-pattern (, (Inheritance $a $b) (Inheritance $a $c)) 26))
(EXPECTED-RESULT canonical-join (frequent-pattern (, (Inheritance $a $b) (Inheritance $c $b)) 34))
