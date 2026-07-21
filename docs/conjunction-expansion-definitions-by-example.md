# Frequent-Miner Definition Map

This is a compact map from `src/frequent-miner.metta` definitions to the facts
they transform. For the full algorithm, read
`docs/conjunction-expansion-walkthrough.md`.

## Support Cycle

```text
freq-pending
  -> freq-support
  -> freq-support-pass
  -> frequent-pattern + freq-expand-check
```

- `freq-support-fn` creates the count query and schedules the rest of the
  current cycle.
- `freq-schedule-filter-fn` installs support pass/save/drop rules.
- `freq-support-pass-fn` compares support with `INPUT MIN-SUPPORT`.
- `freq-save-pass-fn` emits the public result and requests a depth check.
- `freq-drop-fail-fn` consumes the failed branch.

Example:

```text
freq-pending 1 ((Inheritance (var 0) human))
  -> support 4
  -> 4 >= 2
  -> (frequent-pattern (, (Inheritance $a human)) 4)
```

## Expansion Decision

```text
freq-expand-check
  -> freq-expand-pass
  -> freq-expand-todo
```

- `freq-expand-pass-fn` checks `size < MAX-SIZE`.
- `freq-expand-todo-fn` queues a passing candidate for construction.
- `freq-drop-expand-fn` consumes a candidate already at maximum size.

## Pair And Scan

```text
freq-expand-todo + freq-base
  -> freq-expand-pair
  -> freq-scan + partial left shape
  -> completed base shape
  -> freq-conjunct-atom
  -> freq-var-choice ... existing
```

- `freq-expand-pair-fn` pairs each expandable conjunction with every base.
- `freq-pair-details-fn` starts the atom cursor and classifies the left base
  slot.
- `freq-scan-fn` walks an arbitrary number of triplet conjuncts.
- `freq-left-choice-fn` and `freq-right-choice-fn` record indexed variables
  found in either argument position.
- `freq-complete-base-shape-fn` consumes the partial left shape, classifies the
  right slot, and writes the completed shape.

## Fresh Choice

```text
existing v0 -> propose v1 -> drop because existing
existing v1 -> propose v2 -> keep as fresh
```

- `freq-fresh-candidate-fn` proposes every successor.
- `freq-drop-used-fresh-fn` removes successors already in the conjunction.
- `freq-save-fresh-fn` saves the remaining next index.
- `freq-source-relation-fn` records whether a two-variable base repeats the
  same source variable.

## Connected Mapping

The mapping functions emit `freq-connected-base` directly:

| Definition | Accepted mapping |
| --- | --- |
| `freq-map-same-fn` | repeated source, one existing output in both slots |
| `freq-map-distinct-left-fn` | left existing, right existing or fresh |
| `freq-map-distinct-right-fn` | left fresh, right existing |
| `freq-map-left-slot-fn` | left variable chooses existing; right constant stays |
| `freq-map-right-slot-fn` | right variable chooses existing; left constant stays |

There is no disconnected-map fact and no connectivity truth table. A mapping
that uses only fresh variables is never created.

## Candidate Route

```text
freq-connected-base
  -> freq-raw-candidate
  -> freq-sorted-candidate
  -> freq-candidate-vars
  -> freq-candidate
  -> freq-candidate-size
  -> freq-candidate-pass
  -> freq-pending
```

- `freq-build-candidate-fn` unions the connected base with the conjunction.
- `freq-sort-candidate-fn`, `freq-candidate-to-vars-fn`, and
  `freq-alpha-candidate-fn` canonicalize it.
- `freq-candidate-size-fn` measures the canonical candidate.
- `freq-candidate-pass-fn` combines maximum-size and growth checks.
- `freq-queue-candidate-fn` restarts `freq-support-fn` for a passing candidate.
- `freq-drop-candidate-fn` consumes a duplicate/non-growing or oversized one.

## Why Scheduler Definitions Remain

MORK consumes an `exec` when it runs, so later candidate sizes need freshly
scheduled rule instances. Also, substituting every large `DEF` into one rule
exceeds MORK's 64-variable limit. The scheduler definitions are therefore
runtime requirements, not separate business-logic modules.

Every scheduled priority still has the required shape:

```metta
(exec (freq NNN descriptive-label) ...)
```

## Public Versus Temporary Facts

Public:

```metta
(frequent-pattern $pattern $support)
```

Temporary:

```text
every predicate beginning with freq-
```

Temporary facts are consumed by their next stage, stored once inside a cleanup
wrapper removed by the generic build cleanup, or removed by final priority
`freq 900 cleanup-bases`.
