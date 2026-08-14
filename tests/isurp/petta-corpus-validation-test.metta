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
;; PeTTa corpus validation.
;;
;; Mirrors:
;;   hyperon-miner/experiments/surprisingness/tests/test-isurp.metta
;;
;; PeTTa assertion:
;;   (isurp
;;     (, (Inheritance $x man)
;;        (Inheritance $x ugly)
;;        (Inheritance $x sodaDrinker))
;;     &kb
;;     False
;;     0.2)
;;   => 1.9290123456790123e-5
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(INPUT DB db)
(INPUT DB-SIZE 60)
(INPUT NORMALIZATION FALSE)

(INPUT PATTERN
    ((, (Inheritance $x man)
        (Inheritance $x ugly)
        (Inheritance $x sodaDrinker))
     5))

(Inheritance Allen human)
(Inheritance Abe human)
(Inheritance Cason human)
(Inheritance Davion human)
(Inheritance Hessley human)
(Inheritance Jadrian human)
(Inheritance Rio human)
(Inheritance Bob human)
(Inheritance Mike human)
(Inheritance Zac human)
(Inheritance Lily human)
(Inheritance Emily human)
(Inheritance Lucy human)
(Inheritance Sophia human)
(Inheritance Alaura human)
(Inheritance Breonna human)
(Inheritance Jaleesa human)
(Inheritance Jassy human)
(Inheritance Jenica human)
(Inheritance Kecia human)

(Inheritance Allen man)
(Inheritance Abe man)
(Inheritance Cason man)
(Inheritance Davion man)
(Inheritance Hessley man)
(Inheritance Jadrian man)
(Inheritance Rio man)
(Inheritance Bob man)
(Inheritance Mike man)
(Inheritance Zac man)

(Inheritance Lily woman)
(Inheritance Emily woman)
(Inheritance Lucy woman)
(Inheritance Sophia woman)
(Inheritance Alaura woman)
(Inheritance Breonna woman)
(Inheritance Jaleesa woman)
(Inheritance Jassy woman)
(Inheritance Jenica woman)
(Inheritance Kecia woman)

(Inheritance Allen ugly)
(Inheritance Abe ugly)
(Inheritance Cason ugly)
(Inheritance Davion ugly)
(Inheritance Hessley ugly)
(Inheritance Lily ugly)
(Inheritance Emily ugly)
(Inheritance Lucy ugly)
(Inheritance Sophia ugly)
(Inheritance Alaura ugly)

(Inheritance Allen sodaDrinker)
(Inheritance Abe sodaDrinker)
(Inheritance Cason sodaDrinker)
(Inheritance Davion sodaDrinker)
(Inheritance Hessley sodaDrinker)
(Inheritance Breonna sodaDrinker)
(Inheritance Jaleesa sodaDrinker)
(Inheritance Jassy sodaDrinker)
(Inheritance Jenica sodaDrinker)
(Inheritance Kecia sodaDrinker)

(EXPECTED-RESULT petta-corpus-isurp (isurp-new-of (, (Inheritance $a man) (Inheritance $a ugly) (Inheritance $a sodaDrinker)) 1.9290123456790123e-5))
