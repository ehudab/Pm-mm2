# Modular ISurp implementation and validation

## PeTTa source flow

The PeTTa implementation lives in:

```text
../hyperon-miner/experiments/surprisingness/isurp.metta
```

Its public function is:

```metta
(isurp $pattern $db $normalize $db_ratio)
```

For example, PeTTa tests call:

```metta
(isurp
    (, (Inheritance $x man)
       (Inheritance $x ugly)
       (Inheritance $x sodaDrinker))
    &kb
    False
    0.2)
```

The PeTTa test expects:

```metta
1.9290123456790123e-5
```

Internally PeTTa computes:

```text
partitions-wout-pattern(pattern)
-> do-ji-prob(partitions, pattern, db, db_ratio)
-> ji-prob-est(partition, pattern, db, db_ratio)
-> pro-prob-wout-joint(partition, db, db_ratio, 1)
-> eq-prob(partition, pattern, db)
-> ji_prob_est_interval(pattern, db, db_ratio)
-> emp-prob-pbs(pattern, db, emax, db_ratio)
-> dst_from_interval(emin, emax, emp)
-> isurp result
```

The mathematical shape is:

```text
independent probability = product(block empirical probabilities)
joint correction         = eq-prob(partition)
ji probability           = independent probability * joint correction
expected interval        = [min(ji probabilities), max(ji probabilities)]
empirical probability    = observed pattern probability
isurp                    = distance(empirical probability, expected interval)
```

## MM2 module flow

The MM2 implementation is split across small staged files under:

```text
src/isurp_modules/
```

Each `exec` priority uses this project convention:

```metta
(exec (surp <priority> <rule-name>) $source $sink)
```

`surp` is the module namespace, the number controls execution order, and the
last field names the rule.

| File                            | What it does                                                                             |
| ------------------------------- | ---------------------------------------------------------------------------------------- |
| `00_input_bootstrap.metta`      | Converts raw `INPUT PATTERN` into indexed pattern facts.                                 |
| `01_bootstrap_partitions.metta` | Generates `partition`, `block`, and `ji-prob-partitions-of` facts.                       |
| `02_block_support.metta`        | Converts indexed blocks back to query variables and counts block support.                |
| `03_abstractness_sort.metta`    | Scores connected blocks for a joint variable and materializes the most abstract block.   |
| `04_eq_prob.metta`              | Finds joint variables and computes PeTTa-aligned `eq-prob-of`.                           |
| `05_pro_prob_wout_joint.metta`  | Computes independent block probability before joint correction.                          |
| `06_ji_prob_est.metta`          | Computes `ji-prob-est-of = pro-prob-wout-joint-of * eq-prob-of`.                         |
| `07_do_ji_prob.metta`           | Collects `ji-prob-est-of` facts into a probability list for all partitions.              |
| `08_emp_prob_pbs.metta`         | Computes empirical probability directly. Sampling/bootstrap is not implemented here.     |
| `09_isurp_new.metta`            | Builds the JI interval, distance from interval, normalization, and final `isurp-new-of`. |

## MM2 input contract

The full pipeline expects raw DB facts and these input facts:

```metta
(INPUT DB db)
(INPUT DB-SIZE <db-size>)
(INPUT NORMALIZATION TRUE-or-FALSE)
(INPUT PATTERN (<comma-pattern> <support>))
```

Example from `tests/isurp/isurp-pipeline-test.metta`:

```metta
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
```

The pattern support is `1` because only `Allen` satisfies both clauses.

## Running the module

Run the tested pipeline through the project test runner:

```bash
scripts/run-tests.sh tests/isurp/isurp-pipeline-test.metta
```

Run all ISurp module tests:

```bash
scripts/run-tests.sh tests/isurp/*.metta
```

If `mork` is not on `PATH`, pass the binary explicitly:

```bash
MORK_BIN=/path/to/mork scripts/run-tests.sh tests/isurp/*.metta
```

To run manually, load `src/common-utils/utils.metta` and each ISurp module as an
auxiliary input:

```bash
mork run Pattern-miner-mm2/src/common-utils/utils.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/00_input_bootstrap.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/01_bootstrap_partitions.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/02_block_support.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/03_abstractness_sort.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/04_eq_prob.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/05_pro_prob_wout_joint.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/06_ji_prob_est.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/07_do_ji_prob.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/08_emp_prob_pbs.metta \
  --aux-path Pattern-miner-mm2/src/isurp_modules/09_isurp_new.metta \
  --aux-path path/to/input-db.metta
```

## Current MM2 validation case

The current end-to-end MM2 test uses a two-clause pattern:

```metta
(, (Inheritance $x man)
   (Inheritance $x ugly))
```

with four DB facts:

```metta
(Inheritance Allen man)
(Inheritance Bob man)
(Inheritance Allen ugly)
(Inheritance Lily ugly)
```

The MM2 pipeline materializes:

```metta
(indexed-pattern-of
    (, (Inheritance $a man) (Inheritance $a ugly))
    ((Inheritance (var 0) man) (Inheritance (var 0) ugly)))
```

It generates the PeTTa-style partition without the original full pattern:

```metta
(ji-prob-partitions-of
    ((Inheritance (var 0) man) (Inheritance (var 0) ugly))
    ((((Inheritance (var 0) man)) ((Inheritance (var 0) ugly)))))
```

For that partition, block supports are:

```metta
(block-support ... ((Inheritance (var 0) man)) 2)
(block-support ... ((Inheritance (var 0) ugly)) 2)
```

The independent block probabilities are:

```text
P(man block)  = 2 / 4 = 0.5
P(ugly block) = 2 / 4 = 0.5
pro-prob-wout-joint = 0.5 * 0.5 = 0.25
```

The joint variable is `(var 0)`. There are two connected blocks, so the
PeTTa-aligned DB-size fallback is:

```text
eq-prob = 1 / DB-SIZE ^ (connected-block-count - 1)
        = 1 / 4 ^ (2 - 1)
        = 0.25
```

Then:

```text
ji-prob-est = pro-prob-wout-joint * eq-prob
            = 0.25 * 0.25
            = 0.0625
```

The empirical probability uses the current deterministic non-sampling path:

```text
universe-count = DB-SIZE ^ conjunct-count = 4 ^ 2 = 16
support        = 1
emp-prob       = 1 / 16 = 0.0625
```

So the expected interval and empirical probability are the same:

```metta
(ji-prob-est-interval-of
    ((((Inheritance (var 0) man)) ((Inheritance (var 0) ugly))))
    0.0625
    0.0625)

(emp-prob-pbs-of
    (, (Inheritance $a man) (Inheritance $a ugly))
    0.0625)
```

The final distance from the interval is zero:

```metta
(isurp-new-of
    (, (Inheritance $a man) (Inheritance $a ugly))
    0.0)
```

## PeTTa input/output versus MM2 input/output

| System | Input shape                                                | Output shape                                                       | Current documented result                                                       |
| ------ | ---------------------------------------------------------- | ------------------------------------------------------------------ | ------------------------------------------------------------------------------- |
| PeTTa  | `(isurp $pattern $db $normalize $db_ratio)`                | Number                                                             | `1.9290123456790123e-5` for the PeTTa three-clause `man/ugly/sodaDrinker` test. |
| MM2    | `INPUT` facts plus raw DB facts loaded into one MORK Space | Materialized facts, final fact is `(isurp-new-of $pattern $value)` | `0.0` for the current two-clause `man/ugly` pipeline test.                      |

The current MM2 end-to-end test is not the same dataset/pattern as the PeTTa
three-clause validation test, so the numeric outputs are not meant to be equal
in this document. The MM2 test validates that the modular pipeline stages
produce the expected indexed pattern, JI interval, empirical probability, and
final distance for a small controlled case.

## Current scope and differences from PeTTa

- MM2 currently implements the deterministic probability path used by ISurp.
- `emp-prob-pbs` does not include PeTTa's sampling/bootstrap branch yet.
- Clause support is focused on triplet-style clauses such as
  `(Inheritance $x man)`. The clause itself is triplet-shaped; blocks,
  partitions, and partition lists can still contain multiple clauses.
- `eq-prob` uses the PeTTa-aligned DB-size fallback:

```text
factor(var) = 1 / DB-SIZE ^ (connected-block-count(var) - 1)
```

Earlier MM2 versions used support of the most abstract block directly. The
current validation branch changed that because PeTTa validation showed the
DB-size fallback is the aligned behavior for this path.

## Test status

On the current validation branch, the modular ISurp tests pass:

```text
abstractness-sort-test.metta
do-ji-prob-test.metta
emp-prob-pbs-test.metta
eq-prob-test.metta
input-bootstrap-test.metta
isurp-pipeline-test.metta
ji-prob-est-test.metta
partition-bootstrap-test.metta
pro-prob-wout-joint-test.metta
```

Expected runner summary:

```text
Total: 9
Failed: 0
```
