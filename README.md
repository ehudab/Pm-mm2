# Pattern Miner MM2: ISurp Implementation Notes

This repository is the MM2/MORK port of the surprisingness work from `hyperon-miner`.

The current implementation is in:

```text
src/surp.metta
```

The main source implementation in `hyperon-miner` is:

```text
../hyperon-miner/experiments/surprisingness/isurp-old.metta
../hyperon-miner/experiments/surprisingness/isurp.metta
```

Important helper sources are:

```text
../hyperon-miner/experiments/utils/surp-utils/partition-metta.metta
../hyperon-miner/experiments/utils/surp-utils/surp-utils.metta
../hyperon-miner/experiments/utils/surp-utils/binomialMetta.metta
../hyperon-miner/experiments/surprisingness/emp-prob.metta
../hyperon-miner/experiments/utils/surp-utils/eq-prob.metta
../hyperon-miner/experiments/utils/common-utils.metta
```

## Goal

Implement ISurp in MM2 by translating the MeTTa function pipeline into staged MM2 `exec` transactions.

The current MM2 file mostly implements `isurp-old`, not the newer `isurp` with empirical PBS and joint-variable correction.

## Source Algorithm: `isurp-old`

In `hyperon-miner/experiments/surprisingness/isurp-old.metta`, the main function is:

```lisp
(isurp-old $pattern $db $normalize)
```

Its high-level flow is:

```text
pattern
-> total_counts(pattern, db)
-> pattern_prob = prob(pattern, db, total_count)
-> partitions = partitions-wout-pattern(cdr(pattern))
-> result list = isurp-old_(partitions, db, total_count)
-> [emin, emax] = min-max(result list)
-> dst = dst_from_interval(emin, emax, pattern_prob)
-> if normalize:
       min(dst / max(emax, pattern_prob), 1.0)
   else:
       min(dst, 1.0)
```

## Function Inventory and MM2 Mapping

| Source function | Source file | Purpose | Current MM2 equivalent | Status |
|---|---|---|---|---|
| `isurp-old` | `isurp-old.metta` | Top-level old ISurp formula | Whole staged pipeline in `src/surp.metta` | Partial |
| `total_counts` | `isurp-old.metta`, `binomialMetta.metta` | Compute `C(db_size, n_conjuncts)` | `((total-counts ...))` definition, stages 1-2 | Implemented for known `INPUT DB-SIZE` |
| `db_size` | utility/imported behavior | Count atoms in DB | `((count-db ...))` exists, but practical run uses `INPUT DB-SIZE` | Partial |
| `n_conjuncts_new` | `common-utils.metta` | Count conjuncts in `(, ...)` pattern | `((count-conjuncts ...))` using `size-atom (cdr-atom pattern)` | Implemented for comma patterns |
| `cal_binomial` | `binomialMetta.metta` | Binomial count | Uses helper grounding: `falling_factorial / factorial` | Implemented through `MM2-Helper` |
| `prob` | `isurp-old.metta` | `support / total_count` | `((prob ...))` and block-prob stage | Implemented |
| `sup-num` | imported/common behavior | Count matches for a pattern | MM2 dynamic `count` sink | Partial, needs stronger N-ary validation |
| `partitions-wout-pattern` | `partition-metta.metta` | Generate all partitions except the original full pattern | Helper `partitions` on indexed conjunct list | Partial; semantics must match source exactly |
| `blk-prob` | `isurp-old.metta` | Convert block to comma pattern and compute `prob` | Stages 6-7: dynamic query plus `block-prob` | Partial |
| `iprob_` | `isurp-old.metta` | List block probabilities for one partition | Stage 8 product rules | Partial; hard-coded arity |
| `iprob` | `isurp-old.metta` | Multiply block probabilities | Stage 8 `partition-product` | Partial; supports only 2 or 3 blocks |
| `isurp-old_` | `isurp-old.metta` | Compute products for all partitions | Stages 3-9 | Partial; final interval hard-coded for 3 conjuncts |
| `min-max` | utility/imported behavior | Get min/max of product list | Stage 9 `min-atom` / `max-atom` | Partial; hard-coded product collection |
| `dst_from_interval` | `surp-utils.metta` | Distance outside `[emin, emax]` | `((dst-from-interval ...))` plus stages 11-12 | Implemented |
| normalization | `isurp-old.metta` | `min(dst / max(emax, pattern_prob), 1.0)` | Stages 13-16 | Implemented for current outputs |
| cleanup | MM2-specific | Remove temporary facts | Stages 17-19 | Implemented |

## Current MM2 Pipeline

`src/surp.metta` currently uses these stages:

| Stage | What it does |
|---|---|
| Function definitions | Stores reusable exec templates as data: `count-db`, `count-conjuncts`, `total-counts`, `prob`, `dst-from-interval`. |
| `exec 1` | Reads `INPUT DB`, `INPUT PATTERN`, function definitions, spawns counting/probability execs, and indexes variables with `vars_to_indices`. |
| `exec 2` | Generates partitions from the indexed pattern using `partitions`. |
| `exec 3` | Iterates through the list of partitions using `car-atom` / `cdr-atom`. |
| `exec 4` | Copies each partition before block expansion. |
| `exec 5` | Iterates through blocks inside each partition. |
| `exec 6` | Converts indexed block back to variables with `indices_to_vars` and creates a dynamic support-count exec. |
| `exec 7` | Converts `block-support` into `block-prob = support / total-count-of(full-pattern)`. |
| `exec 8` | Multiplies block probabilities into `partition-product`. Currently supports 2-block and 3-block partitions. |
| `exec 9` | Collects four known partition products for a 3-conjunct pattern and computes min/max. |
| `exec 10` | Writes `(partition-product-range $min $max)`. |
| `exec 11-12` | Computes distance from empirical probability to the interval. |
| `exec 13-16` | Applies normalization or raw distance output. |
| `exec 17-19` | Cleanup of temporary facts. |

## Validation Status

See:

```text
docs/isurp-old-validation.md
```

Confirmed passing cases:

| Case | Status |
|---|---|
| `ugly_man_sodaDrinker`, normalization `False` | Pass |
| `ugly_man_sodaDrinker`, normalization `True` | Pass |
| `mock_coupled`, normalization `True` | Pass |

Known blocked cases:

| Case | Blocker |
|---|---|
| 4-conjunct nested pattern | Final product/range stage is hard-coded for 3 conjuncts. |
| N-ary `dataset_for_n_arry_format` patterns | Dynamic support/product pipeline does not yet produce all required `block-support`, `block-prob`, and `partition-product` facts. |

## Necessary Functions to Finish `isurp-old`

These are the minimum functions/pipeline parts that must be completed before the MM2 `isurp-old` port should be considered general.

### 1. Generic Partition Product

Current code has explicit rules:

```lisp
(partition ($b1 $b2))
(partition ($b1 $b2 $b3))
```

Needed behavior:

```text
For any partition with N blocks:
  collect all block-prob facts for that partition
  multiply them
  write (partition-product partition product)
```

Implementation options:

- Add recursive MM2 accumulator over partition blocks.
- Or add a grounded helper such as `product-list-f64`.
- Or generate specialized product execs for each expected block count.

Recommended next step: implement a recursive MM2 accumulator first, because it keeps the logic visible and testable.

### 2. Generic Product Collection for Min/Max

Current code has this 3-conjunct-specific shape:

```lisp
(indexed-pattern ($c1 $c2 $c3))
(partition-product (($c1) ($c2 $c3)) $p1)
(partition-product (($c1 $c3) ($c2)) $p2)
(partition-product (($c1 $c2) ($c3)) $p3)
(partition-product (($c1) ($c2) ($c3)) $p4)
```

Needed behavior:

```text
collect every (partition-product $partition $product)
build a product list
compute min-atom and max-atom over that list
```

Implementation options:

- Create a collection loop that consumes `partition-product` facts into `(product-list (...))`.
- Add a count of expected partitions and stop collection when all have arrived.
- Or use a cleanup-safe "ready" signal after partition expansion finishes.

This is required for 4+ conjunct patterns.

### 3. Exact `partitions-wout-pattern` Semantics

The source function excludes the original full pattern:

```lisp
(= (partitions-wout-pattern $original)
   (exclude-item ($original) (partitions $original)))
```

Current MM2 uses helper `partitions` over indexed conjuncts. Confirm:

- Does it include the full pattern as one partition?
- If yes, exclude it.
- If no, document the helper behavior and add tests proving equivalence.

Necessary tests:

```text
2 conjuncts -> expected independent partitions
3 conjuncts -> expected four old-isurp partitions
4 conjuncts -> expected full non-original partition set
```

### 4. Robust Dynamic Support Query

Current dynamic support query:

```lisp
(indices_to_vars
    (cons , (' $indexed-block)))
```

This works for the simple 3-conjunct examples, but N-ary cases still block.

Needed behavior:

```text
For every block:
  convert indexed variables back to real variables
  construct a comma pattern
  count all matches in the current MORK space
  write exactly one block-support fact
```

Must handle:

- binary atoms like `(Inheritance $x man)`
- nested terms like `(Inheritance (Person $x) man)`
- N-ary atoms like `(Inheritance $x $Interest $Venue)`
- blocks with multiple variables and few constants
- blocks containing more than one conjunct

Recommended debug facts:

```lisp
(debug-query $partition $indexed-block $query)
(debug-support $partition $indexed-block $support)
```

### 5. DB Size Handling

Current validation uses:

```lisp
(INPUT DB-SIZE 60)
```

The source `isurp-old` calls:

```lisp
(db_size $db)
```

Needed behavior:

- Either continue requiring `INPUT DB-SIZE` and document it as an input contract.
- Or make `count-db` authoritative and wire its result into `total-counts`.

Recommended for now: keep `INPUT DB-SIZE` as required input, because it avoids ambiguity about which facts are DB facts versus temporary MM2 facts.

## Additional Functions Needed for Newer `isurp`

The newer source implementation is:

```text
../hyperon-miner/experiments/surprisingness/isurp.metta
```

It is different from `isurp-old`.

Main function:

```lisp
(isurp $pattern $db $normalize $db_ratio)
```

Flow:

```text
ji_prob_est_interval(pattern, db, db_ratio)
-> emp-prob-pbs(pattern, db, emax, db_ratio)
-> dst_from_interval(emin, emax, emp)
-> normalize with max(emp, emax)
```

Functions still needed for the newer `isurp`:

| Source function | Purpose | Required MM2 work |
|---|---|---|
| `pro-prob-wout-joint` | Multiply empirical probabilities of subpatterns while ignoring joint variables | Build product loop over subpatterns or use grounded product helper |
| `ji-prob-est` | Product probability times `eq-prob` correction | Needs `eq-prob` port |
| `do-ji-prob` | Compute `ji-prob-est` for every partition | Similar to generic partition-product loop |
| `ji_prob_est_interval` | Min/max over JI probabilities | Reuse generic product collection/min-max |
| `emp-prob` | `support / universe-count` | Need clear MM2 equivalent for `universe-count` |
| `emp-prob-pbs` | Empirical probability with optional bootstrap/subsample logic | Decide whether to port fully or stub to direct `emp-prob` first |
| `eq-prob` | Correction for variables shared across partition blocks | Large subproject; see below |

## `eq-prob` Backtracking Work

`eq-prob` is the most complex missing dependency for the newer `isurp`.

Source file:

```text
../hyperon-miner/experiments/utils/surp-utils/eq-prob.metta
```

Source flow:

```text
eq-prob(partition, pattern, db)
-> joint-variables(pattern, partition)
-> calculate-prob-for-vars(vars, partition, db, 1.0)
-> connected-subpatterns-with-var(partition, var)
-> sort-by-abstraction(var-partition, var)
-> process-blocks(sorted-partition, var, db, p, 1)
-> find-most-specialized-abstract(...)
-> value-count(block, var, db)
```

Backtracking checklist:

1. Port variable extraction:
   - `get-var`
   - `ret-vars`
   - `get-variables-helper`
   - `get-variables-step`

2. Port joint variable detection:
   - `joint-variables`
   - `joint-vars-helper`
   - `retJointvar`
   - `retJointPat`
   - `retjointSubPat`
   - `checkSubInter`

3. Port connected-subpattern selection:
   - `connected-subpatterns-with-var`
   - `process-pattern`
   - `checkInterSuper`
   - `rmvPar`

4. Define abstraction ordering:
   - Source currently has placeholder:

     ```lisp
     (= (is-blk-more-abstract $head $pivot $var) True)
     ```

   - MM2 should not treat this as complete. A real implementation or documented placeholder is required.

5. Port value counting:
   - `value-count` builds a comma block and counts unique grounded values for a variable.
   - MM2 equivalent must dynamically build:

     ```lisp
     (, block...)
     ```

     then count unique matches of `$var`.

6. Port probability accumulation:
   - `calculate-prob-for-vars`
   - `process-blocks`
   - `find-most-specialized-abstract`

Recommended approach: implement `eq-prob` only after `isurp-old` is generalized. The old pipeline already needs dynamic block support, generic product, and generic min/max; those are prerequisites for the newer path too.

## Proposed Work Breakdown

### Phase 1: Stabilize `isurp-old`

Deliverable: `src/surp.metta` passes all `test-isurp-old.metta` cases that do not require new IIsurp/n-ary interval logic.

Tasks:

1. Add debug mode facts for generated partition, block, query, support, and product.
2. Write small MM2 test fixtures for:
   - 2-conjunct pattern
   - 3-conjunct pattern
   - 4-conjunct pattern
   - N-ary 3-conjunct pattern
3. Replace hard-coded stage 8 product rules with a generic product accumulator.
4. Replace hard-coded stage 9 min/max rule with generic product collection.
5. Confirm `partitions` exactly matches `partitions-wout-pattern`.
6. Fix dynamic support query for N-ary patterns.
7. Re-run validation against:
   - `ugly_man_sodaDrinker`
   - `mock_coupled`
   - `true_nested`
   - `dataset_for_n_arry_format`

### Phase 2: Add Test Harness

Deliverable: repeatable validation files and expected outputs live in this repo.

Tasks:

1. Add MM2 fixtures copied from `hyperon-miner/experiments/surprisingness/tests/test-isurp-old.metta`.
2. Keep expected PeTTa outputs in a markdown table.
3. Add scripts or documented commands for running each fixture with `mork run`.
4. Update `docs/isurp-old-validation.md` after each fix.

### Phase 3: Start New `isurp`

Deliverable: first MM2 version of `ji_prob_est_interval` without PBS.

Tasks:

1. Implement/stub `emp-prob` as direct support divided by universe count.
2. Implement `pro-prob-wout-joint`.
3. Implement `do-ji-prob`.
4. Implement `ji_prob_est_interval`.
5. Use `eq-prob = 1.0` as a temporary placeholder only if documented in output facts.

### Phase 4: Port `eq-prob`

Deliverable: MM2 equivalent of joint-variable correction.

Tasks:

1. Port variable extraction and joint-variable detection.
2. Port connected-subpattern selection.
3. Implement real `is-blk-more-abstract` or document source-equivalent placeholder behavior.
4. Implement `value-count`.
5. Implement `process-blocks`.
6. Validate against `test-isurp.metta` expected values.

### Phase 5: PBS/Subsampling

Deliverable: full `emp-prob-pbs` behavior, or a documented decision that MM2 will use direct empirical probability first.

Tasks:

1. Identify required helpers:
   - `prob_to_support`
   - `subsmp-size`
   - `emp_prob_bs`
   - `emp_prob_helper`
   - `emp_prob_subsmp`
2. Decide whether sampling belongs in MM2 or a grounded helper.
3. Add tests for both direct and sampled paths.

## Current Input Contract for `src/surp.metta`

For now, a runnable MM2 file must provide:

```lisp
(INPUT DB db)
(INPUT DB-SIZE <number-of-db-atoms>)
(INPUT NORMALIZATION TRUE) ; or FALSE
(INPUT PATTERN (<comma-pattern> <support>))
```

Example:

```lisp
(INPUT DB db)
(INPUT DB-SIZE 60)
(INPUT NORMALIZATION TRUE)
(INPUT PATTERN ((, (Inheritance $x man)
                   (Inheritance $x ugly)
                   (Inheritance $x sodaDrinker)) 5))
```

The support in `INPUT PATTERN` must match the support of the full pattern in the DB facts.

## Naming Notes

The current output fact is spelled:

```lisp
(surprisingess-of $pattern $value)
```

This preserves the current implementation spelling. If we rename it later to `surprisingness-of`, update cleanup and validation together.

