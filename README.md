# Hyperon Miner MM2

This repository is the MM2/MORK port of [`hyperon-miner`](https://github.com/iCog-Labs-Dev/hyperon-miner).
The goal is to port the full Hyperon Miner pipeline into MM2 programs that can
run in one MORK atomspace.

## Repository Layout

```text
docs/
  data-model.md              Shared MM2 data model and priority conventions
  isurp-old-validation.md    Validation notes against PeTTa isurp-old
  testing.md                 Test file format and runner workflow

data/
  frequent-miner/            Frequent-miner test fixtures
  ugly-sodaDrinker.metta     Surprisingness test fixture

src/
  surp.metta                 Current MM2 implementation of isurp-old
  frequent-miner.metta       Frequent mining and connected expansion
  dummy.metta                Scratch file

tests/
  frequent-miner/            Runnable frequent-miner test cases
  surp/                      Runnable surprisingness test cases

scripts/
  run-tests.sh               Test runner for *-test.metta files
```

## Dependencies

This project expects a MORK build with the local [`mm2-helper`](https://github.com/iCog-Labs-Dev/MM2-Helper) extensions and
[`mm2-stdlib`](https://github.com/abnsol/mm2-stdlib) helpers available.



## Running Tests

Run all test cases:

```sh
scripts/run-tests.sh
```

Run one test case:

```sh
scripts/run-tests.sh tests/frequent-miner/conjunction-expansion-test.metta
```

Use `MORK_BIN` when `mork` is not on `PATH`:

```sh
MORK_BIN=/path/to/mork scripts/run-tests.sh
```

Test files keep runner metadata in MM2 comments:

```metta
;; TEST-AUX data/ugly-sodaDrinker.metta
;; TEST-AUX src/surp.metta

(EXPECTED-RESULT test-id (...))
```

See `docs/testing.md` for the full test guide.

## Frequent Miner

The frequent miner accepts triplet seed patterns plus two configuration facts:

```metta
(INPUT MIN-SUPPORT 2)
(INPUT MAX-SIZE 3)
(pattern 0 (Inheritance $x human))
```

Its only public result is a canonical conjunction with support:

```metta
(frequent-pattern (, (Inheritance $a human)) 4)
```

Conjunction expansion is an internal stage of the `freq` module. It is not a
third project module. See `docs/conjunction-expansion-walkthrough.md` for the
algorithm and `justMine/` for worked examples.
