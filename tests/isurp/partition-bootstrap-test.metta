;; TEST-AUX src/common-utils/utils.metta
;; TEST-AUX src/isurp_modules/01_bootstrap_partitions.metta

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Partition/bootstrap component test
;;
;; This test validates only the first ISurp module:
;;
;;   raw INPUT PATTERN
;;   -> indexed-pattern
;;   -> ji-prob-partitions-of
;;   -> partition
;;   -> block
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(INPUT DB db)
(INPUT DB-SIZE 4)

(INPUT PATTERN
    ((, (Inheritance $x man)
        (Inheritance $x ugly)
        (Inheritance $x sodaDrinker))
     1))

(EXPECTED-RESULT indexed-pattern-3 (indexed-pattern-of (, (Inheritance $a man) (Inheritance $a ugly) (Inheritance $a sodaDrinker)) ((Inheritance (var 0) man) (Inheritance (var 0) ugly) (Inheritance (var 0) sodaDrinker))))

(EXPECTED-RESULT partition-list-3 (ji-prob-partitions-of ((Inheritance (var 0) man) (Inheritance (var 0) ugly) (Inheritance (var 0) sodaDrinker)) ((((Inheritance (var 0) man)) ((Inheritance (var 0) ugly) (Inheritance (var 0) sodaDrinker))) (((Inheritance (var 0) man) (Inheritance (var 0) sodaDrinker)) ((Inheritance (var 0) ugly))) (((Inheritance (var 0) man) (Inheritance (var 0) ugly)) ((Inheritance (var 0) sodaDrinker))) (((Inheritance (var 0) man)) ((Inheritance (var 0) ugly)) ((Inheritance (var 0) sodaDrinker))))))

(EXPECTED-RESULT partition-first (partition (((Inheritance (var 0) man)) ((Inheritance (var 0) ugly) (Inheritance (var 0) sodaDrinker)))))

(EXPECTED-RESULT partition-singletons (partition (((Inheritance (var 0) man)) ((Inheritance (var 0) ugly)) ((Inheritance (var 0) sodaDrinker)))))

(EXPECTED-RESULT block-first-single (block (((Inheritance (var 0) man)) ((Inheritance (var 0) ugly) (Inheritance (var 0) sodaDrinker))) ((Inheritance (var 0) man))))

(EXPECTED-RESULT block-first-pair (block (((Inheritance (var 0) man)) ((Inheritance (var 0) ugly) (Inheritance (var 0) sodaDrinker))) ((Inheritance (var 0) ugly) (Inheritance (var 0) sodaDrinker))))
