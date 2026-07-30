;; TEST-AUX src/common-utils/utils.metta
;; TEST-AUX src/isurp_modules/00_input_bootstrap.metta
;; TEST-AUX src/isurp_modules/01_bootstrap_partitions.metta
;; TEST-AUX src/isurp_modules/02_block_support.metta
;; TEST-AUX src/isurp_modules/03_abstractness_sort.metta
;; TEST-AUX src/isurp_modules/04_eq_prob.metta
;; TEST-AUX src/isurp_modules/05_pro_prob_wout_joint.metta
;; TEST-AUX src/isurp_modules/06_ji_prob_est.metta
;; TEST-AUX src/isurp_modules/07_do_ji_prob.metta
;; TEST-AUX src/isurp_modules/08_emp_prob_pbs.metta
;; TEST-AUX src/isurp_modules/09_isurp_new.metta

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Full modular ISurp pipeline test
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(INPUT DB db)
(INPUT DB-SIZE 4)
(INPUT NORMALIZATION FALSE)

(INPUT PATTERN
    ((, (Inheritance $x man)
        (Inheritance $x ugly))
     1))

(Inheritance Allen man)
(Inheritance Bob man)
(Inheritance Allen ugly)
(Inheritance Lily ugly)

(EXPECTED-RESULT indexed-pattern (indexed-pattern-of (, (Inheritance $a man) (Inheritance $a ugly)) ((Inheritance (var 0) man) (Inheritance (var 0) ugly))))

(EXPECTED-RESULT ji-interval (ji-prob-est-interval-of ((((Inheritance (var 0) man)) ((Inheritance (var 0) ugly)))) 0.0625 0.0625))

(EXPECTED-RESULT isurp-pipeline (isurp-new-of (, (Inheritance $a man) (Inheritance $a ugly)) 0.0))
