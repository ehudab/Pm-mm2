;; TEST-AUX benchmarks/MIND/data/MIND_behaviors_ClickedSmall.metta
;; TEST-AUX src/common-utils/utils.metta
;; TEST-AUX src/freq/frequent-miner.metta
;; TEST-AUX src/freq/iterative-miner.metta
;; TEST-AUX src/freq/conjunction-expansion-triplet.metta
;; TEST-AUX src/freq/frequent-pattern-miner.metta


(INPUT DB db)
(INPUT MIN-SUPPORT 2)
(INPUT MAX-SIZE 3)
(INPUT SUPPORT-MODE cached)

;; The iterative miner consumes FACT wrappers; conjunction expansion consumes
;; the raw triplets loaded from the same fixture.
(exec (freq 000 materialize-frequent-miner-facts)
  (, (Clicked $user $news))
  (O (+ (FACT (Clicked $user $news)))))

(run-frequent-pattern-miner integration-test (Clicked $x $y))

(exec (freq 001 call-frequent-pattern-miner)
  (, (run-frequent-pattern-miner integration-test (Clicked $x $y))
     (DEF frequent-pattern-miner-fn $miner-p $miner-t))
  (O (+ (exec (freq 002 run-frequent-pattern-miner) $miner-p $miner-t))))
