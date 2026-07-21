# Testing Guide

Tests are written as runnable MM2 files. Each test file is the main input to
`mork run`, while implementation and data files are loaded through `TEST-AUX`
metadata comments.

## Test File Shape

Use this structure for each test:

```metta
;; TEST-AUX data/example-data.metta
;; TEST-AUX src/example-module.metta

(INPUT ...)

(EXPECTED-RESULT test-id expected-fact)
```

The runner reads `TEST-AUX` comments, runs MORK, then checks that every
`expected-fact` appears as a standalone fact in the final output.

## Adding A New Module Test

1. Create a test file under `tests/<module>/`.

```text
tests/frequent-miner/basic-test.metta
```

2. Add the required data and source files as aux paths.

```metta
;; TEST-AUX data/frequent-miner-basic.metta
;; TEST-AUX src/frequent-miner.metta
```

3. Add the input facts expected by the module.

```metta
(INPUT DB db)
(INPUT MIN-SUPPORT 3)
```

4. Add one or more expected results.

```metta
(EXPECTED-RESULT frequent-miner-basic (frequent-pattern (, (Inheritance $x human)) 10))
```

The first argument after `EXPECTED-RESULT` is the test identifier. The second
argument is the fact that must be present in the final MORK output.

5. Run all tests.

```sh
scripts/run-tests.sh
```

6. Or run only the new test.

```sh
scripts/run-tests.sh tests/frequent-miner/basic-test.metta
```

