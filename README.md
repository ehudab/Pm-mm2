# Hyperon Miner MM2

This repository is the MM2/MORK port of [`hyperon-miner`](../hyperon-miner).
The goal is to port the full Hyperon Miner pipeline into MM2 programs that can
run in one MORK atomspace.

## Repository Layout

```text
docs/
  data-model.md              Shared MM2 data model and priority conventions
  isurp-old-validation.md    Validation notes against PeTTa isurp-old

src/
  surp.metta                 Current MM2 implementation of isurp-old
  frequent-miner.metta       Early frequent-miner/helper work
  dummy.metta                Scratch file, currently empty
```

## Dependencies

This project expects a MORK build with the local MM2 helper extensions and
`mm2-stdlib` helpers available.

## Running The Current Surprisingness Program

Run the sample data embedded in `src/surp.metta`:

```sh
mork run src/surp.metta /tmp/hyperon-miner-mm2-surp-out.metta --steps 200 --instrumentation 0
```

Then inspect the final result:

```sh
rg "surprisingess-of" /tmp/hyperon-miner-mm2-surp-out.metta
```

Expected sample result:

```metta
(surprisingess-of ... 0.999707773232028)
```

## Running Tests

Run all test cases:

```sh
scripts/run-tests.sh
```

Use `MORK_BIN` when `mork` is not on `PATH`:

```sh
MORK_BIN=/path/to/mork scripts/run-tests.sh
```
