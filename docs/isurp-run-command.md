# ISurp Modular Run Command

MORK loads one main input file and any number of auxiliary files into the same
Space.  The CLI argument is repeatable:

```bash
mork run <main-file> --aux-path <extra-file-1> --aux-path <extra-file-2>
```

For the split ISurp implementation, use `src/common-utils/utils.metta` as the
main file and load the ISurp implementation modules with `--aux-path`.

## Runner-Based Tests

The ISurp tests are regular project runner tests.  Run all modular ISurp tests:

```bash
scripts/run-tests.sh tests/isurp/abstractness-sort-test.metta \
  tests/isurp/eq-prob-test.metta \
  tests/isurp/pro-prob-wout-joint-test.metta \
  tests/isurp/ji-prob-est-test.metta \
  tests/isurp/do-ji-prob-test.metta \
  tests/isurp/emp-prob-pbs-test.metta \
  tests/isurp/isurp-pipeline-test.metta
```

Or run one component test:

```bash
scripts/run-tests.sh tests/isurp/eq-prob-test.metta
```

## Full ISurp Pipeline

Use this shape when the input DB file provides the full ISurp input contract:

```metta
(INPUT DB db)
(INPUT DB-SIZE <db-size>)
(INPUT NORMALIZATION TRUE)
(INPUT PATTERN (<comma-pattern> <support>))
```

Run:

```bash
mork run Pattern-miner-mm2/src/common-utils/utils.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/01_bootstrap_partitions.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/02_block_support.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/03_abstractness_sort.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/04_eq_prob.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/05_pro_prob_wout_joint.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/06_ji_prob_est.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/07_do_ji_prob.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/08_emp_prob_pbs.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/09_isurp_new.metta \
  --aux-path path/to/your-isurp-input-db.metta
```

Each component test keeps its fixture data and expected facts in one runnable
file under `tests/isurp/`.

## Module Map

ISurp stages use readable tuple priorities:

```metta
(exec (surp <priority> <function-name>) $sources $sinks)
```

`surp` is the module namespace, `<priority>` controls execution order, and
`<function-name>` describes the rule.

| File | Purpose |
| --- | --- |
| `src/common-utils/utils.metta` | Shared reusable function-definition facts such as `count-db`, `prob`, `total-counts`, and `dst-from-interval`. |
| `01_bootstrap_partitions.metta` | Starts the ISurp pipeline, indexes variables, generates partitions, and expands partitions into blocks. |
| `02_block_support.metta` | Computes `block-support` facts for generated partition blocks. |
| `03_abstractness_sort.metta` | Selects the most abstract connected block for each joint variable using triplet-level syntactic scoring and deterministic fallbacks. |
| `04_eq_prob.metta` | Detects shared variables across blocks and computes `eq-prob-of`. |
| `05_pro_prob_wout_joint.metta` | Computes `pro-prob-wout-joint` product probability before joint-variable correction. |
| `06_ji_prob_est.metta` | Multiplies `pro-prob-wout-joint-of` by `eq-prob-of` to produce `ji-prob-est-of`. |
| `07_do_ji_prob.metta` | Collects `ji-prob-est-of` facts into an ordered probability list for a requested partition list. |
| `08_emp_prob_pbs.metta` | Computes direct empirical probability for the input pattern without sampling/bootstrap logic. |
| `09_isurp_new.metta` | Connects the newer helper facts into `ji-prob-est-interval-of`, distance, and final `isurp-new-of`. |

The legacy monolithic `src/isurp.metta` has been removed.  Use the modular
command above so each shared utility and ISurp stage is loaded explicitly.
