# Common MM2 Utilities

`utils.metta` contains reusable rule templates shared by the pattern-miner
pipelines. It does not define a third module or own exec priorities. A caller
matches a template, chooses its output predicate, and schedules the returned
source and sink.

Load it from a test with:

```metta
;; TEST-AUX src/common-utils/utils.metta
```

## Functions

### `count-db`

```metta
((count-db $db-name -> $out) $source $sink)
```

Counts facts stored as `($db-name $fact)` and writes:

```metta
($out $db-name $count)
```

### `count-conjuncts`

```metta
((count-conjuncts $pattern -> $out) $source $sink)
```

Reads `(INPUT PATTERN ($pattern $support))`, removes the leading comma from the
conjunction, and writes its number of atoms as:

```metta
($out $pattern $count)
```

### `total-counts`

```metta
((total-counts $db $pattern -> $out) $source $sink)
```

Reads `INPUT DB-SIZE` and a previously produced `num-of-conjuncts` fact. It
computes the binomial count:

```text
C(n, k) = falling_factorial(n, k) / factorial(k)
```

and writes `(total-count-of $pattern $total)`.

### `prob`

```metta
((prob $pattern $db -> $out) $source $sink)
```

Divides the support from `INPUT PATTERN` by `total-count-of` and writes:

```metta
($out $pattern $probability)
```

### `dst-from-interval`

```metta
((dst-from-interval $pattern $emin $emax $emp -> $out) $source $sink)
```

Consumes a `dst-request` and classifies the empirical value relative to the
closed interval `[emin, emax]`. It writes the three boolean branch facts used
by `surp.metta`:

```metta
(dst-above? ... true-or-false)
(dst-below? ... true-or-false)
(dst-inside? ... true-or-false)
```

## Dependencies

These utilities expect MORK to register:

- `mm2-stdlib` for list operations, numeric conversion, comparison, division,
  and boolean helpers;
- MM2-Helper for `factorial` and `falling_factorial`.

The current regression example is `tests/surp/isurp-old-test.metta`, which
loads this file through `TEST-AUX` before loading `src/surp.metta`.
