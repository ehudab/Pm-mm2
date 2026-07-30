;; TEST-AUX src/isurp_modules/01_bootstrap_partitions.metta

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Partition component test
;;
;; This test validates only partition generation:
;;
;;   indexed-pattern
;;   -> ji-prob-partitions-of
;;   -> partition
;;   -> block
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(indexed-pattern
    ((Inheritance (var 0) man)
     (Inheritance (var 0) ugly)
     (Inheritance (var 0) sodaDrinker)))

(EXPECTED-RESULT partition-list-3 (ji-prob-partitions-of ((Inheritance (var 0) man) (Inheritance (var 0) ugly) (Inheritance (var 0) sodaDrinker)) ((((Inheritance (var 0) man)) ((Inheritance (var 0) ugly) (Inheritance (var 0) sodaDrinker))) (((Inheritance (var 0) man) (Inheritance (var 0) sodaDrinker)) ((Inheritance (var 0) ugly))) (((Inheritance (var 0) man) (Inheritance (var 0) ugly)) ((Inheritance (var 0) sodaDrinker))) (((Inheritance (var 0) man)) ((Inheritance (var 0) ugly)) ((Inheritance (var 0) sodaDrinker))))))

(EXPECTED-RESULT partition-first (partition (((Inheritance (var 0) man)) ((Inheritance (var 0) ugly) (Inheritance (var 0) sodaDrinker)))))

(EXPECTED-RESULT partition-singletons (partition (((Inheritance (var 0) man)) ((Inheritance (var 0) ugly)) ((Inheritance (var 0) sodaDrinker)))))

(EXPECTED-RESULT block-first-single (block (((Inheritance (var 0) man)) ((Inheritance (var 0) ugly) (Inheritance (var 0) sodaDrinker))) ((Inheritance (var 0) man))))

(EXPECTED-RESULT block-first-pair (block (((Inheritance (var 0) man)) ((Inheritance (var 0) ugly) (Inheritance (var 0) sodaDrinker))) ((Inheritance (var 0) ugly) (Inheritance (var 0) sodaDrinker))))
