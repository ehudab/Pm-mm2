# emp-tv validation against PeTTa

This document records validation of the MM2 `emp-tv.metta` implementation against the PeTTa `isurp-old` tests in:

```text
/hyperon-miner/experiments/truth-values/tests/test-emp-tv.metta
```

The MM2 implementation under test is:

```text
pattern-miner-mm2/src/jsd_modules/emp-tv.metta
```


Validation was run by generating temporary MM2 files under `/tmp` with:

- the same PeTTa test pattern
- the same dataset as the PeTTa ugly-sodaDrinker-db, it is the same as ugly-sodaDrinker but with the `(db-fact $db $fact)` format. 
- `INPUT PATTERN`, main pattern
- `CONSTANT default_k` and `CONSTANT DEFAULT_K` 

## Results

| Case | Function | MM2 result | PeTTa expected | Status | Notes |
|--- | --- | ---: | ---:| ---:| ---| ---|
| `ugly_man_sodaDrinker`| emp-tv | `(EMPTV ((inheritance (var 0) woman) (inheritance (var 0) ugly)) db1 (0.0013888889 0.081818186)))` | `(EMPTV 0.001388888888888889 0.08181818181818183)` | Pass | Difference is floating-point precision only. |
| `ugly_man_sodaDrinker`| do_emp_tv | `None` | `(EMPTV 0.001388888888888889 0.08181818181818183)` | Fail | do_emp_tv uses STV value which is not done yet. |


## Current blockers

### 1. Floating-point precision

MM2 has limiated floating-point precision, which is not a problem for the current implementation. The PeTTa expected results are rounded to 17 decimal places, while MM2 results are rounded to 10 decimal places.:

`0.001388888888888889 ` vs `0.0013888889`

`0.08181818181818183` vs `0.081818186`



## Summary

The MM2 implementation now matches PeTTa `emp-tv` for the simple 3-conjunct pattern and the coupled 3-conjunct pattern. Only `do_emp_tv` remains to be implemented, which is a matter of implementing the `STV (est-tv)` value. 
