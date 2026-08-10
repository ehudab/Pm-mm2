;; TEST-AUX src/common-utils/utils.metta
;; TEST-AUX src/jsd_modules/init.metta
;; TEST-AUX src/jsd_modules/emp-tv.metta
;; TEST-AUX data/ugly-sodaDrinker-db.metta

(INPUT PATTERN ((, (inheritance (var 0) woman) (inheritance (var 0) ugly) (inheritance (var 0) sodaDrinker)) 5))
(INPUT DB db1)

(CONSTANT default_k 800.0)
(CONSTANT DEFAULT_K 800.0)



(EXPECTED-RESULT emp-tv (EMPTV ((inheritance (var 0) woman) (inheritance (var 0) ugly)) db1 (0.0013888889 0.081818186)))
