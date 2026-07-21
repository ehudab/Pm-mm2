# Connected Expansion Inside `freq`

Connected conjunction expansion is a stage of the frequent miner. It does not
have its own module namespace or source file. The implementation lives in
`src/frequent-miner.metta`, and every owned priority begins with `freq`.

## Contract

The miner reads configuration and triplet seed patterns:

```metta
(INPUT MIN-SUPPORT 2)
(INPUT MAX-SIZE 3)
(pattern 0 (Parent $x $y))
```

Database facts are active facts in the same atomspace:

```metta
(Parent Alice Bob)
(Parent Bob Carol)
```

The only public miner result is:

```metta
(frequent-pattern (, (Parent $a $b) (Parent $b $c)) 4)
```

All `freq-*` facts are temporary and are consumed before priority `900`
finishes.

## Why Patterns Are Indexed Internally

MM2 variables are useful for support queries but awkward as durable data. The
miner therefore normalizes each seed with `vars_to_indices`:

```text
(Parent $x $y)
    ->
(Parent (var 0) (var 1))
```

A conjunction is stored as a list of indexed atoms:

```metta
((Parent (var 0) (var 1))
 (Parent (var 1) (var 2)))
```

Before support counting or public output, `indices_to_vars` turns the markers
back into a real query and `cons` adds the conjunction head:

```metta
(, (Parent $a $b) (Parent $b $c))
```

## Pipeline

The important priority bands are:

| Band | Purpose |
| --- | --- |
| `freq 010-020` | Normalize seeds and start mining |
| `freq 100-141` | Count support and keep frequent candidates |
| `freq 200-221` | Decide whether a frequent candidate may grow |
| `freq 300-374` | Pair candidates with bases and find variable choices |
| `freq 400-431` | Generate connected bases, union them, and clean build state |
| `freq 500-531` | Canonicalize, reject non-growth, and queue the next size |
| `freq 900` | Remove normalized bases after recursion ends |

Dynamic `DEF` bodies are scheduled in these bands because MORK consumes an
`exec` after it runs. A newly generated size-2 candidate therefore needs a new
support-cycle exec. The small scheduler definitions also keep substituted
rules below MORK's 64-variable limit.

## Support And Depth

`freq-pending` holds one indexed candidate awaiting support counting:

```metta
(freq-pending 2
  ((Parent (var 0) (var 1))
   (Parent (var 1) (var 2))))
```

The miner converts it to a query, uses MORK's `count` sink, and compares the
text support with `INPUT MIN-SUPPORT`. Passing candidates produce one
`frequent-pattern` result and one `freq-expand-check` request.

A candidate expands only when:

```text
current size < MAX-SIZE
```

A newly constructed candidate is queued only when both conditions hold:

```text
new size <= MAX-SIZE
new size > old size
```

The second condition removes unions where the chosen base was already present.

## Connected Variant Generation

Suppose the current conjunction is:

```metta
((Parent (var 0) (var 1)))
```

and the normalized base is:

```metta
(Parent (var 0) (var 1))
```

The scanner finds the existing variables `(var 0)` and `(var 1)`. Because
indices are contiguous, it proposes each successor and removes proposals that
already exist. The remaining successor is the one fresh choice, `(var 2)`.

Choices are therefore:

```text
(var 0) existing
(var 1) existing
(var 2) fresh
```

A base variant is connected when at least one variable slot chooses an
`existing` variable. The implementation generates only such mappings:

- repeated source variable: one existing choice is used in both slots;
- distinct source variables: left existing/right any, or left fresh/right
  existing;
- one variable plus one constant: the variable must choose existing;
- two constants: no connected mapping exists.

This directly excludes `(Parent (var 2) (var 2))`, whose only variable is
fresh, without creating a connectivity fact and later deleting it.

For example, the mapping:

```text
left  -> (var 1) existing
right -> (var 2) fresh
```

creates:

```metta
(Parent (var 1) (var 2))
```

Unioning that base with the old conjunction creates the connected chain:

```metta
((Parent (var 0) (var 1))
 (Parent (var 1) (var 2)))
```

## Repeated Variables

The base shape matters. For:

```metta
(Knows (var 0) (var 0))
```

both occurrences came from the same source variable, so they must receive the
same output choice. A cleanup-wrapped `freq-source-same` relationship records
this equality. The same-source mapping rule emits `(Knows V V)` only; it never
emits `(Knows V W)`.

## Canonicalization And Deduplication

The raw union passes through three grounded operations:

1. `sort-atom` gives conjunction atoms a stable order.
2. `indices_to_vars` restores real variable identity.
3. `vars_to_indices` reindexes by first occurrence.

These calls remain separate because quoted list results are not safely
composable as one nested MM2 expression. After the three stages,
alpha-equivalent candidates become the same exact fact and MORK's set behavior
deduplicates them.

## Cleanup

Build state that must survive several mapping stages is stored once inside a
`freq-cleanup` wrapper. Mapping rules match the nested shape, choice, or source
relationship directly. At priority `430`, one generic rule removes each
wrapper. Facts used by only one next stage are consumed directly. Priority
`900` removes `freq-base` after every recursively queued lower-priority cycle
has completed.

The final test outputs contain public `frequent-pattern` facts but no `freq-*`
facts.

## Tests

The executable example is
`tests/frequent-miner/conjunction-expansion-test.metta`. It covers constant
slots, connected size-2 and size-3 parent chains, repeated variables, and
representative canonical outputs from the retired standalone implementation.

Run them with:

```sh
scripts/run-tests.sh tests/frequent-miner/conjunction-expansion-test.metta
```

The implementation currently accepts triplet atoms. `MAX-SIZE` limits the
number of conjuncts, not the arity of each seed atom.
