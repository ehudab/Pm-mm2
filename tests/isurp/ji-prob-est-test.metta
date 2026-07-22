;; TEST-AUX src/isurp_modules/03_abstractness_sort.metta
;; TEST-AUX src/isurp_modules/04_eq_prob.metta
;; TEST-AUX src/isurp_modules/05_pro_prob_wout_joint.metta
;; TEST-AUX src/isurp_modules/06_ji_prob_est.metta

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; ji-prob-est component test
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(INPUT DB-SIZE 4)

(partition (((Inheritance (var 0) man)) ((Inheritance (var 0) ugly))))

(block
    (((Inheritance (var 0) man)) ((Inheritance (var 0) ugly)))
    ((Inheritance (var 0) man)))

(block
    (((Inheritance (var 0) man)) ((Inheritance (var 0) ugly)))
    ((Inheritance (var 0) ugly)))

(block-support
    (((Inheritance (var 0) man)) ((Inheritance (var 0) ugly)))
    ((Inheritance (var 0) man))
    2)

(block-support
    (((Inheritance (var 0) man)) ((Inheritance (var 0) ugly)))
    ((Inheritance (var 0) ugly))
    2)

(Inheritance Allen man)
(Inheritance Bob man)
(Inheritance Allen ugly)
(Inheritance Lily ugly)

(EXPECTED-RESULT ji-prob-est (ji-prob-est-of (((Inheritance (var 0) man)) ((Inheritance (var 0) ugly))) 0.125))
