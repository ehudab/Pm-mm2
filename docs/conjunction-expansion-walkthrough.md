# Conjunction Expansion Walkthrough

This document explains the file:

```text
Pattern-miner-mm2/src/conjunction-expansion-triplet.metta
```

The goal is to make the code readable even if the names, staging logic, and
MM2 execution style are new to you.

## Big Picture

Conjunction expansion means:

```text
Start with single patterns.
Combine them into larger AND-style patterns.
Keep only combinations that appear often enough in the database.
Repeat until the configured maximum size is reached.
```

Example input patterns:

```lisp
(Inheritance $x human)
(Inheritance $x ugly)
(Inheritance $x sodaDrinker)
```

Possible expanded conjunction:

```lisp
(,
  (Inheritance $x human)
  (Inheritance $x ugly)
  (Inheritance $x sodaDrinker))
```

That means:

```text
Find people who are human AND ugly AND soda drinkers.
```

The code does not only build combinations. It also counts how many database
matches each combination has, then filters out weak combinations.

## What The File Produces

The main output facts are:

```lisp
(expanded-conjunct $size $candidate $support)
```

Meaning:

| Field | Meaning |
|---|---|
| `$size` | How many pattern atoms are inside the conjunction |
| `$candidate` | The conjunction itself, stored in indexed form |
| `$support` | How many matches it has in the database |

For example, a result could mean:

```text
This 3-part conjunction matched 2 times in the database.
```

## Important Vocabulary

| Word | Meaning |
|---|---|
| Pattern | A query shape, such as `(Inheritance $x human)` |
| Conjunct | One part of an AND expression |
| Conjunction | Several conjuncts joined together |
| Candidate | A possible conjunction we are testing |
| Support | The number of database matches for a candidate |
| Threshold | The minimum support required to keep a candidate |
| Depth | The maximum number of conjuncts allowed |
| Indexed form | Variables rewritten as numbers, such as `(var 0)` |
| Canonical form | A normalized atom order and variable numbering so duplicates collapse |

## Why Variables Are Converted To Indices

The source patterns use readable variables:

```lisp
(Inheritance $x human)
(Inheritance $x $y)
```

The expansion code converts them with:

```lisp
vars_to_indices
```

So this:

```lisp
(Inheritance $x human)
```

becomes conceptually like:

```lisp
(Inheritance (var 0) human)
```

This matters because the program needs to know when two variable positions are
the same variable.

For example:

```lisp
(,
  (Inheritance $x human)
  (Inheritance $x ugly))
```

means the same `$x` must satisfy both facts. It is not enough to find any human
and any ugly thing separately. The same database entity must match both.

Later, when support is counted, the code converts indexed variables back with:

```lisp
indices_to_vars
```

That gives MM2 a real query it can count.

## Why The File Says "Triplet-Only"

This line near the top matters:

```lisp
;; Generic triplet-only conjunction expansion for the MM2 pattern miner.
```

"Triplet" means the code accepts pattern atoms shaped like this:

```lisp
($predicate $left $right)
```

Examples:

```lisp
(Inheritance $x human)
(Similarity apple orange)
(Likes $person soda)
```

Each one has:

```text
predicate + left argument + right argument
```

The file intentionally starts from this input shape:

```lisp
(pattern 0 ($predicate $left $right))
```

That means it does not currently accept arbitrary longer atoms like:

```lisp
(Loves $x $interest $venue)
```

That would be an N-ary pattern, not a triplet.

## The Short Version Of The Algorithm

The code repeats this cycle:

```text
1. Read base patterns.
2. Normalize variables into indexed form.
3. Queue each single pattern as a pending candidate.
4. Count candidate support.
5. Keep candidates whose support is high enough.
6. Save kept candidates as expanded-conjunct facts.
7. If candidate size is still below max depth, expand it.
8. Build bigger candidates by adding connected variants of base patterns.
9. Sort candidate atoms so duplicate orders collapse.
10. Re-index variables so alpha-equivalent candidates collapse.
11. Queue the bigger candidate and repeat.
```

Visual flow:

```text
pattern
  |
  v
ce-base + ce-pending
  |
  v
support count
  |
  v
support threshold check
  |
  +--> fail: drop it
  |
  +--> pass: save as expanded-conjunct
              |
              v
          depth check
              |
              +--> at max depth: stop expanding
              |
              +--> below max depth: build connected base variants
                                      |
                                      v
                                canonical candidate
                                      |
                                      v
                                new pending candidate
```

## Prefix Cheat Sheet

Most names start with `ce`.

```text
ce = conjunction expansion
```

Examples:

| Name | Meaning |
|---|---|
| `ce-base` | A normalized single base pattern |
| `ce-pending` | A candidate waiting for support counting |
| `ce-support` | A candidate with its counted support |
| `ce-support-pass` | Whether the candidate passed the support threshold |
| `ce-conjunct` | A frequent conjunction saved by the algorithm |
| `ce-expand-check` | A saved candidate that may need further expansion |
| `ce-expand-todo` | A candidate approved for expansion |
| `ce-connected-map` | A variable mapping that connects a base to the old candidate |
| `ce-connected-base` | A base pattern after applying a connected variable mapping |
| `ce-raw-candidate` | A newly built candidate before canonicalization |
| `ce-sorted-candidate` | Candidate after atom-order sorting |
| `ce-candidate-vars` | Sorted candidate temporarily converted back to real variables |
| `ce-candidate` | Candidate after sorting and alpha-normalized variable indexing |
| `ce-candidate-size` | The size of a candidate |

## Why There Are Many Small Functions

The file is written as a pipeline. Each function does one small step and creates
facts for the next step.

For example:

```text
ce-support
  -> ce-support-i32
  -> ce-support-pass
  -> ce-conjunct / expanded-conjunct
```

This style is useful in MM2 because facts are added and removed over time.
Instead of one large function doing everything, each stage leaves behind a
simple fact that the next stage can consume.

## The Meaning Of `exec`

An `exec` block is a rule that runs when its input pattern matches existing
facts.

Simplified shape:

```lisp
(exec PRIORITY
    INPUT
    OUTPUT)
```

The input says:

```text
Run this when these facts exist.
```

The output says:

```text
Add facts, remove facts, or compute grounded helper results.
```

In this file, priorities look like:

```lisp
(CE 0 0)
(CE 1 0)
(CE 2 0)
```

These are used to force the pipeline to happen in a stable order.

## The Meaning Of `DEF`

The file defines reusable rule bodies with:

```lisp
(DEF ce-support-fn ...)
```

Then later it schedules them by adding facts like:

```lisp
(+ (exec (CE 1 0) $support-p $support-t))
```

This lets the file dynamically schedule the next part of the pipeline.

In plain English:

```text
Store this rule definition.
Later, add an exec that runs that rule.
```

## The Meaning Of `O`, `+`, `-`, And `pure`

Inside an output block:

```lisp
(O
  (+ something)
  (- something)
  (pure ...))
```

The pieces mean:

| Syntax | Meaning |
|---|---|
| `O` | A group of output actions |
| `+` | Add a fact |
| `-` | Remove a fact |
| `pure` | Run a deterministic helper and bind its result |

Example:

```lisp
(+ (ce-pending $size $candidate))
```

means:

```text
Add this candidate to the queue.
```

Example:

```lisp
(- (ce-pending $size $candidate))
```

means:

```text
Remove this candidate from the queue so it is not processed again.
```

Example:

```lisp
(pure
    (ce-candidate-size $old-size $candidate $size)
    $size
    (size-atom (' $candidate)))
```

means:

```text
Compute the size of the candidate.
Save the result as a ce-candidate-size fact.
```

## Stage 0: Configuration And Seeds

The first pipeline stage converts configuration strings into numbers:

```lisp
(support-threshold $threshold)
(depth-of-conjunct $max-depth)
```

These are converted with:

```lisp
i32_from_string
```

Why? Because support and depth comparisons use integer comparison helpers:

```lisp
ge_i32
lt_i32
le_i32
gt_i32
```

Then the code reads triplet patterns:

```lisp
(pattern 0 ($predicate $left $right))
```

For each pattern, it creates two facts:

```lisp
(ce-base $indexed)
(ce-pending 1 ($indexed))
```

Meaning:

```text
This pattern is a base pattern.
Also test this pattern alone as a size-1 candidate.
```

## Stage 1: Count Support

The support function starts from:

```lisp
(ce-pending $size $candidate)
```

It removes that pending fact:

```lisp
(- (ce-pending $size $candidate))
```

Then it counts matches:

```lisp
(count
    (ce-support $size $candidate $support)
    $support
    $query)
```

The query is built by converting the indexed candidate back into normal
variables:

```lisp
indices_to_vars
```

So a candidate can be stored safely as indexed data but still counted as a real
MM2 query.

## Stage 2: Support Threshold

The count result is text, so it is converted:

```lisp
i32_from_string
```

Then the code checks:

```lisp
support >= threshold
```

Using:

```lisp
ge_i32
```

If it passes, the code saves:

```lisp
(ce-conjunct $size $candidate $support)
(expanded-conjunct $size $candidate $support)
(ce-expand-check $size $candidate $support)
```

If it fails, the code removes the temporary pass/fail fact and does not expand
the candidate.

## Stage 3: Depth Check

The file should not expand forever.

So every passing candidate is checked against:

```lisp
(depth-of-conjunct $max-depth)
```

The rule is:

```text
Only expand if current size < max depth.
```

That is why the code uses:

```lisp
lt_i32
```

If the candidate is already at max depth, it is saved but not expanded further.

## Stage 4: Build Bigger Candidates

When a candidate is approved for expansion, the code pairs it with every base
pattern:

```lisp
(ce-expand-todo $old-size $conjunct)
(ce-base $base)
```

It does not add the base exactly as written. First it builds connected variants
of the base by mapping the base variables onto:

```text
existing variables from the old candidate
or the next fresh variable
```

At least one mapped position must use an existing variable. That is what makes
the new base connected to the old candidate.

Example old candidate:

```lisp
((Parent (var 0) (var 1)))
```

Example base:

```lisp
(Parent (var 0) (var 1))
```

Useful connected variants include:

```lisp
(Parent (var 1) (var 2))
(Parent (var 0) (var 2))
(Parent (var 2) (var 0))
```

But this disconnected variant is rejected:

```lisp
(Parent (var 2) (var 3))
```

because neither side touches `(var 0)` or `(var 1)` from the old candidate.

After a connected base variant is built, the code unions it with the old
candidate and creates:

```lisp
(ce-raw-candidate $old-size $raw)
```

This is the new bigger candidate before cleanup.

Conceptually:

```text
old candidate + one connected base variant = bigger candidate
```

Example:

```text
[(Inheritance $x human)]
  + (Inheritance $x ugly)
  =
[(Inheritance $x human), (Inheritance $x ugly)]
```

## Why `union-atom` Is Used

The code uses:

```lisp
union-atom
```

instead of simply adding with `cons`.

The reason is duplicate prevention.

After the connected base variant is built, `union-atom` prevents duplicate atoms
inside one conjunction.

If a candidate already contains:

```lisp
(Inheritance $x human)
```

and the code tries to add the same base again, `union-atom` keeps it from
becoming a duplicate-filled candidate.

So this should not happen:

```text
[human, human, ugly]
```

Instead, the candidate only grows when a genuinely new conjunct is added.

## Why `sort-atom` Is Used

The same conjunction can be built in different orders:

```text
[human, ugly]
[ugly, human]
```

Logically, these mean the same thing:

```text
human AND ugly
ugly AND human
```

So the code canonicalizes the order:

```lisp
sort-atom
```

After sorting, both versions get the same atom order. This prevents duplicates
that differ only by conjunct order.

## Why Alpha-Normalization Is Used

Sorting handles order duplicates, but not every duplicate shape.

These two candidates are alpha-equivalent:

```lisp
((Parent (var 0) (var 1))
 (Inheritance (var 0) (var 2)))
```

```lisp
((Parent (var 0) (var 2))
 (Inheritance (var 0) (var 1)))
```

They differ only by swapping the names of `(var 1)` and `(var 2)`. Logically
they ask the same query.

The code handles this without a Rust helper by staging two existing conversions
after sorting:

```lisp
indices_to_vars
vars_to_indices
```

First, the sorted indexed candidate is converted back into real MM2 variables.
Then it is converted back to indexed form. That second conversion assigns
`(var 0)`, `(var 1)`, `(var 2)` by first occurrence in the sorted candidate.

So alpha-equivalent candidates collapse to the same exact stored `ce-candidate`
before size checks and support counting.

## Why Candidate Size Is Checked Twice

After building a candidate, the code computes its size:

```lisp
size-atom
```

Then it checks two things:

```text
1. Did the candidate actually grow?
2. Is the candidate still within max depth?
```

Growth check:

```lisp
gt_i32 $size-i32 $old-size-i32
```

This filters out cases where `union-atom` did not add anything new.

Depth check:

```lisp
le_i32 $size-i32 $max-depth-i32
```

This prevents candidates bigger than the configured maximum.

Only candidates that pass both checks are queued again:

```lisp
(ce-pending $size $candidate)
```

Then another support-count cycle is scheduled.

## The Demo Inputs At The Bottom

The bottom of the file contains a tiny runnable example:

```lisp
(pattern 0 (Inheritance $x human))
(pattern 0 (Inheritance $x $y))
(pattern 0 (Inheritance $x ugly))
(pattern 0 (Inheritance $x sodaDrinker))

(depth-of-conjunct 3)
(support-threshold 2)
```

Then it includes database facts like:

```lisp
(Inheritance Allen human)
(Inheritance Allen ugly)
(Inheritance Allen sodaDrinker)
```

This lets the file be run by itself while developing.

When used as part of a bigger pipeline, this bottom demo section should be
replaced by real caller inputs.

## A Complete Example In Plain English

Suppose the database says:

```text
Allen is human, ugly, and a soda drinker.
Bob is human and ugly.
Dana is human, ugly, and a soda drinker.
```

And the threshold is:

```text
support must be at least 2
```

Then:

```text
human
```

passes because Allen, Bob, Cason, and Dana match.

```text
human AND ugly
```

passes because Allen, Bob, and Dana match.

```text
human AND ugly AND sodaDrinker
```

passes because Allen and Dana match.

But a combination that only matches one person fails when threshold is 2.

## Main Assumptions In The New File

The code assumes:

1. Input pattern atoms are triplets.
2. Variables can safely be normalized with `vars_to_indices`.
3. Indexed variables can be converted back with `indices_to_vars` for counting.
4. Support counts can be converted to `i32`.
5. Conjunction order does not matter, so sorting is valid.
6. Variable names do not matter beyond equality structure, so alpha-normalization is valid.
7. Duplicate conjuncts should not increase candidate size.
8. A new base must connect to the old candidate through at least one existing variable.
9. A candidate should only continue expanding if it is frequent enough.
10. Expansion stops at `depth-of-conjunct`.

## How To Read The Source File

Read it in this order:

1. Start at the bottom demo inputs so you know what data goes in.
2. Read the Stage 0 pipeline rules that create `ce-base` and `ce-pending`.
3. Read `ce-support-fn` to see how candidates are counted.
4. Read the support threshold functions.
5. Read the depth check functions.
6. Read the candidate building functions.
7. Return to `ce-support-fn` and notice how it schedules the next stages.

That order is easier than reading strictly top to bottom.

## One-Screen Mental Model

Keep this in mind:

```text
ce-pending
  means "please test this candidate"

ce-support
  means "we counted it"

ce-support-pass
  means "we checked if it is frequent enough"

expanded-conjunct
  means "this is a real output"

ce-expand-todo
  means "try to make this candidate bigger"

ce-raw-candidate
  means "a connected base variant was unioned with the old candidate"

ce-sorted-candidate / ce-candidate-vars
  means "the candidate is being canonicalized"

ce-candidate
  means "a bigger candidate was fully normalized"

ce-pending again
  means "test the bigger candidate next"
```

The whole file is that loop.
