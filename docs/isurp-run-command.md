# ISurp Modular Run Command

MORK loads one main input file and any number of auxiliary files into the same
Space.  The CLI argument is repeatable:

```bash
mork run <main-file> --aux-path <extra-file-1> --aux-path <extra-file-2>
```

For the split ISurp implementation, use `00_defs.metta` as the main file and
load the remaining implementation modules with `--aux-path`.

## EQ-prob-only test

```bash
mork run Pattern-miner-mm2/src/isurp_modules/00_defs.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/01_bootstrap_partitions.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/02_eq_prob.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/04_pro_prob_wout_joint.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/05_ji_prob_est.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/06_do_ji_prob.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/07_emp_prob_pbs.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/08_isurp_new.metta \
  --aux-path Pattern-miner-mm2/tests/eq-prob-db.metta
```

Expected important facts:

```metta
(eq-joint-var (((Inheritance (var 0) man)) ((Inheritance (var 0) ugly))) (var 0))
(eq-var-factor (((Inheritance (var 0) man)) ((Inheritance (var 0) ugly))) (var 0) 0.5)
(eq-prob-of (((Inheritance (var 0) man)) ((Inheritance (var 0) ugly))) 0.5)
```

## Full old-ISurp pipeline

Use this shape when the input DB file provides the full ISurp input contract:

```metta
(INPUT DB db)
(INPUT DB-SIZE <db-size>)
(INPUT NORMALIZATION TRUE)
(INPUT PATTERN (<comma-pattern> <support>))
```

Run:

```bash
mork run Pattern-miner-mm2/src/isurp_modules/00_defs.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/01_bootstrap_partitions.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/02_eq_prob.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/03_old_isurp_pipeline.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/04_pro_prob_wout_joint.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/05_ji_prob_est.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/06_do_ji_prob.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/07_emp_prob_pbs.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/08_isurp_new.metta \
  --aux-path path/to/your-isurp-input-db.metta
```

## pro-prob-wout-joint-only test

```bash
mork run Pattern-miner-mm2/src/isurp_modules/04_pro_prob_wout_joint.metta \
  --aux-path Pattern-miner-mm2/tests/pro-prob-wout-joint-db.metta
```

Expected important facts:

```metta
(pro-block-prob (((Inheritance (var 0) man)) ((Inheritance (var 0) ugly))) ((Inheritance (var 0) man)) 0.5)
(pro-block-prob (((Inheritance (var 0) man)) ((Inheritance (var 0) ugly))) ((Inheritance (var 0) ugly)) 0.5)
(pro-prob-wout-joint-of (((Inheritance (var 0) man)) ((Inheritance (var 0) ugly))) 0.25)
```

## ji-prob-est-only test

```bash
mork run Pattern-miner-mm2/src/isurp_modules/02_eq_prob.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/04_pro_prob_wout_joint.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/05_ji_prob_est.metta \
  --aux-path Pattern-miner-mm2/tests/ji-prob-est-db.metta
```

Expected important facts:

```metta
(eq-prob-of (((Inheritance (var 0) man)) ((Inheritance (var 0) ugly))) 0.5)
(pro-prob-wout-joint-of (((Inheritance (var 0) man)) ((Inheritance (var 0) ugly))) 0.25)
(ji-prob-est-of (((Inheritance (var 0) man)) ((Inheritance (var 0) ugly))) 0.125)
```

## do-ji-prob-only test

```bash
mork run Pattern-miner-mm2/src/isurp_modules/06_do_ji_prob.metta \
  --aux-path Pattern-miner-mm2/tests/do-ji-prob-db.metta
```

Expected important fact:

```metta
(do-ji-prob-of ((((Inheritance (var 0) man)) ((Inheritance (var 0) ugly))) (((Inheritance (var 0) man) (Inheritance (var 0) ugly)))) (0.125 0.25))
```

## emp-prob-pbs-only test

This MM2 version intentionally uses only direct empirical probability.  It does
not implement the PeTTa sampling/bootstrap branch.

```bash
mork run Pattern-miner-mm2/src/isurp_modules/07_emp_prob_pbs.metta \
  --aux-path Pattern-miner-mm2/tests/emp-prob-pbs-db.metta
```

Expected important facts:

```metta
(emp-prob-pbs-universe-count (, (Inheritance (var 0) man) (Inheritance (var 0) ugly)) 16)
(emp-prob-pbs-of (, (Inheritance (var 0) man) (Inheritance (var 0) ugly)) 0.25)
```

## newer ISurp integration test

```bash
mork run Pattern-miner-mm2/src/isurp_modules/00_defs.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/01_bootstrap_partitions.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/02_eq_prob.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/03_old_isurp_pipeline.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/04_pro_prob_wout_joint.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/05_ji_prob_est.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/06_do_ji_prob.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/07_emp_prob_pbs.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/08_isurp_new.metta \
  --aux-path Pattern-miner-mm2/tests/isurp-new-db.metta
```

Expected important facts:

```metta
(ji-prob-est-interval-of ((((Inheritance (var 0) man)) ((Inheritance (var 0) ugly)))) 0.125 0.125)
(emp-prob-pbs-of (, (Inheritance (var 0) man) (Inheritance (var 0) ugly)) 0.0625)
(isurp-new-of (, (Inheritance (var 0) man) (Inheritance (var 0) ugly)) 0.0625)
```

## Module Map

| File | Purpose |
| --- | --- |
| `00_defs.metta` | Reusable function-definition facts such as `count-db`, `prob`, `total-counts`, and `dst-from-interval`. |
| `01_bootstrap_partitions.metta` | Starts the old-ISurp pipeline, indexes variables, generates partitions, and expands partitions into blocks. |
| `02_eq_prob.metta` | Detects shared variables across blocks and computes `eq-prob-of`. |
| `03_old_isurp_pipeline.metta` | Computes block support, block probability, partition probability products, interval distance, normalization, and cleanup for the old ISurp pipeline. |
| `04_pro_prob_wout_joint.metta` | Computes the newer `pro-prob-wout-joint` product probability before joint-variable correction. |
| `05_ji_prob_est.metta` | Multiplies `pro-prob-wout-joint-of` by `eq-prob-of` to produce `ji-prob-est-of`. |
| `06_do_ji_prob.metta` | Collects `ji-prob-est-of` facts into an ordered probability list for a requested partition list. |
| `07_emp_prob_pbs.metta` | Computes direct empirical probability for the input pattern without sampling/bootstrap logic. |
| `08_isurp_new.metta` | Connects the newer helper facts into `ji-prob-est-interval-of`, distance, and final `isurp-new-of`. |

The original `src/isurp.metta` is kept as the monolithic single-file version.
