# Conjunction Expansion: Definitions By Example

This file explains the actual code in:

```text
Pattern-miner-mm2/src/conjunction-expansion-triplet.metta
```

The first walkthrough explained the idea. This file is more direct: it goes
definition by definition, block by block, and shows what happens using the demo
inputs at the bottom of the source file.

## Demo Inputs We Will Use

The source file currently ends with these pattern inputs:

```lisp
(pattern 0 (Inheritance $x human))
(pattern 0 (Inheritance $x $y))
(pattern 0 (Inheritance $x ugly))
(pattern 0 (Inheritance $x sodaDrinker))
```

And these settings:

```lisp
(depth-of-conjunct 3)
(support-threshold 2)
```

And this database:

```lisp
(Inheritance Allen human)
(Inheritance Allen ugly)
(Inheritance Allen sodaDrinker)
(Inheritance Bob human)
(Inheritance Bob ugly)
(Inheritance Cason human)
(Inheritance Cason sodaDrinker)
(Inheritance Dana human)
(Inheritance Dana ugly)
(Inheritance Dana sodaDrinker)
```

So the miner is being told:

```text
Build conjunctions up to size 3.
Only keep a candidate if it matches at least 2 times.
```

## Current Expansion Behavior

Two implementation details matter for the current file:

1. Expansion is connected. A base pattern is not simply unioned into the old
   candidate as written. The code builds variable mappings for the base and
   keeps only mappings where at least one base variable is mapped to an existing
   variable in the old candidate.
2. Candidate canonicalization has two parts. `sort-atom` removes order
   duplicates, then `indices_to_vars` followed by `vars_to_indices` removes
   alpha-equivalent duplicates by re-indexing variables in first-occurrence
   order.

So these two candidates collapse to the same stored candidate:

```lisp
((Parent (var 0) (var 1))
 (Inheritance (var 0) (var 2)))
```

```lisp
((Parent (var 0) (var 2))
 (Inheritance (var 0) (var 1)))
```

They differ only by the names of the non-shared variables.

## Useful Example Supports

Before reading the definitions, keep these counts in mind.

### Single Patterns

```lisp
(Inheritance $x human)
```

Matches:

```text
Allen, Bob, Cason, Dana
```

Support:

```text
4
```

```lisp
(Inheritance $x ugly)
```

Matches:

```text
Allen, Bob, Dana
```

Support:

```text
3
```

```lisp
(Inheritance $x sodaDrinker)
```

Matches:

```text
Allen, Cason, Dana
```

Support:

```text
3
```

```lisp
(Inheritance $x $y)
```

Matches every database fact because `$x` and `$y` can be anything.

Support:

```text
10
```

### Two-Part Conjunctions

```lisp
(,
  (Inheritance $x human)
  (Inheritance $x ugly))
```

Matches:

```text
Allen, Bob, Dana
```

Support:

```text
3
```

```lisp
(,
  (Inheritance $x human)
  (Inheritance $x sodaDrinker))
```

Matches:

```text
Allen, Cason, Dana
```

Support:

```text
3
```

```lisp
(,
  (Inheritance $x ugly)
  (Inheritance $x sodaDrinker))
```

Matches:

```text
Allen, Dana
```

Support:

```text
2
```

### Three-Part Conjunction

```lisp
(,
  (Inheritance $x human)
  (Inheritance $x ugly)
  (Inheritance $x sodaDrinker))
```

Matches:

```text
Allen, Dana
```

Support:

```text
2
```

This passes because the threshold is `2`.

## Lines 1-9: File Comment

The source starts with:

```lisp
;; Generic triplet-only conjunction expansion for the MM2 pattern miner.
;;
;; The working representation is indexed:
;;
;;   (Inheritance $x human)  ->  (Inheritance (var 0) human)
;;
;; Indexed conjuncts are saved and expanded at every frequent level. Support
;; counting converts each indexed conjunct back into a real MM2 query with
;; indices_to_vars, so repeated variables are respected by the count sink.
```

Meaning:

```text
The code accepts triplet atoms like (Inheritance $x human).
Internally it does not keep raw variable names like $x.
It rewrites variables into stable numbered variables.
When it needs to count support, it turns the numbered variables back into a query.
```

Concrete example:

```lisp
(Inheritance $x human)
```

becomes conceptually:

```lisp
(Inheritance (var 0) human)
```

Then, for counting, it becomes a normal query again:

```lisp
(Inheritance $x human)
```

The reason is variable consistency. In:

```lisp
(,
  (Inheritance $x human)
  (Inheritance $x ugly))
```

the same `$x` must match both facts.

## Lines 22-47: `ce-support-fn`

Source shape:

```lisp
(DEF ce-support-fn
    INPUT
    OUTPUT)
```

This definition starts a support-count cycle for one queued candidate.

### Lines 22-23

```lisp
(DEF ce-support-fn
    (, (ce-pending $size $candidate)
```

This means:

```text
This function runs when there is a pending candidate.
```

Example pending candidate:

```lisp
(ce-pending 1 ((Inheritance (var 0) human)))
```

That means:

```text
Please test this size-1 candidate:
(Inheritance $x human)
```

### Lines 24-27

```lisp
(DEF ce-schedule-support-filter-fn $support-filter-p $support-filter-t)
...
(DEF ce-schedule-candidate-result-fn $candidate-result-p $candidate-result-t)
```

These lines load the compact scheduler definitions into variables.

For example:

```lisp
(DEF ce-schedule-support-filter-fn $support-filter-p $support-filter-t)
```

means:

```text
Get the input pattern and output template of ce-schedule-support-filter-fn.
Store them in $support-filter-p and $support-filter-t.
```

Why? Because this function will schedule those functions as later `exec` rules.

### Line 28

```lisp
(O
```

This starts the output actions.

Everything inside this `O` either:

```text
adds a fact,
removes a fact,
or computes a helper result.
```

### Line 29

```lisp
(- (ce-pending $size $candidate))
```

Remove the pending candidate being processed.

With our example:

```lisp
(- (ce-pending 1 ((Inheritance (var 0) human))))
```

Why remove it? So the same candidate is not counted again and again.

### Lines 30-40

```lisp
(pure
    (exec (CE 1 1)
        $query
        (O
            (count
                (ce-support $size $candidate $support)
                $support
                $query)))
    $query
    (indices_to_vars
        (cons , (' $candidate))))
```

This creates a new `exec` rule that will count support.

The important part is:

```lisp
(indices_to_vars
    (cons , (' $candidate)))
```

For this candidate:

```lisp
((Inheritance (var 0) human))
```

it builds the query:

```lisp
(, (Inheritance $x human))
```

Then the generated `exec` does:

```lisp
(count
    (ce-support 1 ((Inheritance (var 0) human)) $support)
    $support
    (, (Inheritance $x human)))
```

The database has 4 humans, so it creates:

```lisp
(ce-support 1 ((Inheritance (var 0) human)) 4)
```

Another example:

```lisp
(ce-pending 2
  ((Inheritance (var 0) human)
   (Inheritance (var 0) ugly)))
```

gets converted into a real query:

```lisp
(,
  (Inheritance $x human)
  (Inheritance $x ugly))
```

That matches Allen, Bob, and Dana, so it creates:

```lisp
(ce-support 2
  ((Inheritance (var 0) human)
   (Inheritance (var 0) ugly))
  3)
```

### Lines 42-47

```lisp
(+ (exec (CE 2 0) $support-filter-p $support-filter-t))
(+ (exec (CE 3 0) $expansion-check-p $expansion-check-t))
(+ (exec (CE 4 0) $build-candidate-p $build-candidate-t))
(+ (exec (CE 6 0) $candidate-result-p $candidate-result-t))
```

These schedule the next compact scheduler rules.

In plain English:

```text
After counting support:
1. Schedule support conversion, thresholding, saving, and failure cleanup.
2. Schedule depth checks for saved frequent candidates.
3. Schedule connected candidate construction.
4. Schedule candidate canonicalization, size checks, queueing, and cleanup.
```

## Lines 51-61: `ce-schedule-support-filter-fn`

```lisp
(+ (exec (CE 2 1) $support-to-i32-p $support-to-i32-t))
(+ (exec (CE 2 2) $support-pass-p $support-pass-t))
(+ (exec (CE 2 3) $save-pass-p $save-pass-t))
(+ (exec (CE 2 4) $drop-fail-p $drop-fail-t))
```

These schedule the support-filtering steps.

In plain English:

```text
After counting support:
1. Convert support to an integer.
2. Compare support to the threshold.
3. Save passing candidates.
4. Drop failing candidates.
```

## Lines 64-74: `ce-schedule-expansion-check-fn`

```lisp
(+ (exec (CE 3 1) $expand-size-p $expand-size-t))
(+ (exec (CE 3 2) $expand-pass-p $expand-pass-t))
(+ (exec (CE 3 3) $expand-todo-p $expand-todo-t))
(+ (exec (CE 3 4) $drop-expand-p $drop-expand-t))
```

These schedule the depth-checking steps.

In plain English:

```text
After a candidate passes support:
1. Convert its size to an integer.
2. Check whether size < max depth.
3. If yes, queue it for expansion.
4. If no, stop expanding it.
```

Example:

```text
size = 1, max depth = 3
1 < 3 is true
so expand it
```

But:

```text
size = 3, max depth = 3
3 < 3 is false
so save it but do not expand it
```

## Lines 78-96: `ce-schedule-candidate-result-fn`

```lisp
(+ (exec (CE 6 1) $sort-candidate-p $sort-candidate-t))
...
(+ (exec (CE 6 8) $drop-candidate-p $drop-candidate-t))
```

These schedule candidate canonicalization, size checking, queueing, and cleanup
after raw connected candidates have been emitted.

In plain English:

```text
For candidates approved for expansion:
1. Sort candidate atoms.
2. Convert indexed vars to real vars, then back to indexed vars.
3. Compute candidate size.
4. Convert sizes to integers.
5. Check growth and max depth.
6. Queue good candidates.
7. Drop bad candidates.
```

## Lines 99-106: `ce-support-to-i32-fn`

Source:

```lisp
(DEF ce-support-to-i32-fn
    (, (ce-support $size $candidate $support))
    (O
        (pure
            (ce-support-i32 $size $candidate $support $support-i32)
            $support-i32
            (i32_from_string $support))
        (- (ce-support $size $candidate $support))))
```

Input example:

```lisp
(ce-support 1 ((Inheritance (var 0) human)) 4)
```

Line by line:

```lisp
(, (ce-support $size $candidate $support))
```

means:

```text
Run when a support result exists.
```

```lisp
(i32_from_string $support)
```

converts text-like support into an integer value. With the example:

```text
"4" -> integer 4
```

Then it creates:

```lisp
(ce-support-i32 1 ((Inheritance (var 0) human)) 4 <binary-i32-4>)
```

The last line:

```lisp
(- (ce-support $size $candidate $support))
```

removes the old text support fact.

Why? The next stage should use the integer-ready fact.

## Lines 109-117: `ce-support-pass-fn`

Source:

```lisp
(DEF ce-support-pass-fn
    (, (ce-support-i32 $size $candidate $support $support-i32)
       (ce-threshold-i32 $threshold $threshold-i32))
    (O
        (pure
            (ce-support-pass $size $candidate $support $pass)
            $pass
            (ge_i32 $support-i32 $threshold-i32))
        (- (ce-support-i32 $size $candidate $support $support-i32))))
```

This compares:

```text
support >= threshold
```

Example:

```text
support = 4
threshold = 2
4 >= 2 is true
```

So it creates:

```lisp
(ce-support-pass 1 ((Inheritance (var 0) human)) 4 true)
```

For a failing candidate with support 1, it would create:

```lisp
(ce-support-pass 2 SOME-CANDIDATE 1 false)
```

Then it removes:

```lisp
(ce-support-i32 ...)
```

because the pass/fail result is now the useful fact.

## Lines 120-126: `ce-save-pass-fn`

Source:

```lisp
(DEF ce-save-pass-fn
    (, (ce-support-pass $size $candidate $support true))
    (O
        (+ (ce-conjunct $size $candidate $support))
        (+ (expanded-conjunct $size $candidate $support))
        (+ (ce-expand-check $size $candidate $support))
        (- (ce-support-pass $size $candidate $support true))))
```

This only runs for candidates that passed support.

Example input:

```lisp
(ce-support-pass 1 ((Inheritance (var 0) human)) 4 true)
```

It adds:

```lisp
(ce-conjunct 1 ((Inheritance (var 0) human)) 4)
(expanded-conjunct 1 ((Inheritance (var 0) human)) 4)
(ce-expand-check 1 ((Inheritance (var 0) human)) 4)
```

Meaning:

```text
This candidate is frequent.
Save it as an output.
Also check whether it should be expanded further.
```

Then it removes:

```lisp
(ce-support-pass 1 ((Inheritance (var 0) human)) 4 true)
```

## Lines 129-132: `ce-drop-fail-fn`

Source:

```lisp
(DEF ce-drop-fail-fn
    (, (ce-support-pass $size $candidate $support false))
    (O
        (- (ce-support-pass $size $candidate $support false))))
```

This runs only for candidates that failed.

Example:

```lisp
(ce-support-pass 2 SOME-CANDIDATE 1 false)
```

It removes that fact and does not save or expand the candidate.

In plain English:

```text
Not frequent enough. Throw it away.
```

## Lines 135-141: `ce-expand-size-to-i32-fn`

Source:

```lisp
(DEF ce-expand-size-to-i32-fn
    (, (ce-expand-check $size $candidate $support))
    (O
        (pure
            (ce-expand-size-i32 $size $candidate $support $size-i32)
            $size-i32
            (i32_from_string $size))))
```

This prepares the candidate size for comparison.

Example input:

```lisp
(ce-expand-check 1 ((Inheritance (var 0) human)) 4)
```

It converts:

```text
1 -> integer 1
```

and creates:

```lisp
(ce-expand-size-i32 1 ((Inheritance (var 0) human)) 4 <binary-i32-1>)
```

It does not remove `ce-expand-check` yet because the next function needs both
facts together.

## Lines 144-154: `ce-expand-pass-fn`

Source:

```lisp
(DEF ce-expand-pass-fn
    (, (ce-expand-check $size $candidate $support)
       (ce-expand-size-i32 $size $candidate $support $size-i32)
       (ce-max-depth-i32 $max-depth $max-depth-i32))
    (O
        (pure
            (ce-expand-pass $size $candidate $pass)
            $pass
            (lt_i32 $size-i32 $max-depth-i32))
        (- (ce-expand-check $size $candidate $support))
        (- (ce-expand-size-i32 $size $candidate $support $size-i32))))
```

This checks:

```text
current size < max depth
```

With the demo settings:

```text
max depth = 3
```

For a size-1 candidate:

```text
1 < 3 = true
```

So it creates:

```lisp
(ce-expand-pass 1 ((Inheritance (var 0) human)) true)
```

For a size-3 candidate:

```text
3 < 3 = false
```

So it creates:

```lisp
(ce-expand-pass 3 SOME-CANDIDATE false)
```

That means:

```text
The candidate is already saved as an output, but do not make it bigger.
```

## Lines 157-161: `ce-expand-todo-fn`

Source:

```lisp
(DEF ce-expand-todo-fn
    (, (ce-expand-pass $size $candidate true))
    (O
        (+ (ce-expand-todo $size $candidate))
        (- (ce-expand-pass $size $candidate true))))
```

This turns a passing depth check into actual expansion work.

Example:

```lisp
(ce-expand-pass 1 ((Inheritance (var 0) human)) true)
```

becomes:

```lisp
(ce-expand-todo 1 ((Inheritance (var 0) human)))
```

Meaning:

```text
Try adding every base pattern to this candidate.
```

## Lines 164-167: `ce-drop-expand-fn`

Source:

```lisp
(DEF ce-drop-expand-fn
    (, (ce-expand-pass $size $candidate false))
    (O
        (- (ce-expand-pass $size $candidate false))))
```

This cleans up candidates that reached max depth.

Example:

```lisp
(ce-expand-pass 3 SOME-CANDIDATE false)
```

is removed. Nothing else is added.

The candidate was already saved by `ce-save-pass-fn`, so this is not deleting
the output. It is only stopping further expansion.

## Lines 173-658: Connected Candidate Building

This whole block takes a frequent candidate that is still below max depth and
tries to make larger candidates from it.

Important rule:

```text
The new base atom must connect to the old candidate through at least one
existing variable.
```

So the code does not simply append every base pattern. It first creates possible
variable mappings, rejects disconnected mappings, and only then unions the
connected base variant with the old candidate.

The important shape is:

```text
ce-expand-todo
  -> ce-expand-pair
  -> ce-var-choice
  -> ce-base-var-map
  -> ce-connected-map
  -> ce-connected-base
  -> ce-raw-candidate
```

Use this running example:

```lisp
(ce-expand-todo 1 ((Inheritance (var 0) human)))
(ce-base (Inheritance (var 0) ugly))
```

The desired connected result is:

```lisp
((Inheritance (var 0) human)
 (Inheritance (var 0) ugly))
```

That means:

```text
Find things that are human and ugly, sharing the same variable.
```

### Lines 173-183: `ce-build-candidate-fn`

This is the top-level scheduler for expansion work.

Input:

```lisp
(ce-expand-todo $old-size $conjunct)
```

It does not build candidates itself. Think of it as opening four work lanes for
the same active `ce-expand-todo`.

First, it schedules the pair-preparation lane. That lane pairs the old candidate
with every `ce-base`, extracts the atoms already inside the old candidate, and
records the shape of the base atom.

Second, it schedules the choice lane. That lane turns the variables already
present in the old candidate into possible connection points and also computes
the one next fresh variable.

Third, it schedules the map lane. That lane tries the possible ways to replace
the base atom's variable slots with existing or fresh variables, then labels
each map as connected or disconnected.

Fourth, it schedules the output lane. That lane rebuilds only connected base
variants, unions them with the old candidate, and clears the temporary facts
used during this expansion.

The indirection exists because each scheduled rule has a smaller variable
capture set. That keeps the generated rules under MORK's rule-size limits.

### Lines 187-199: `ce-schedule-pair-build-fn`

This scheduler prepares enough information for later rules to decide how a base
atom may attach to the old candidate.

It starts by scheduling `ce-expand-pair-fn`. When that rule runs, it takes the
active old candidate and combines it with each known `ce-base`. For the running
example, it creates a pair saying:

```text
Try old candidate ((Inheritance (var 0) human))
with base atom     (Inheritance (var 0) ugly).
```

Then `ce-expand-pair-details-fn` creates a cursor whose remaining list starts as
the complete old candidate. `ce-expand-pair-scan-fn` repeatedly reads the first
atom with `car-atom`, replaces the remaining list with `cdr-atom`, and schedules
itself again. Each pass emits one `ce-conjunct-atom` fact. Because termination is
the empty remaining list rather than a hard-coded tuple shape, this works for
any candidate size accepted by `depth-of-conjunct`.

For the running example, the scan emits:

```lisp
(ce-conjunct-atom
  1
  ((Inheritance (var 0) human))
  (Inheritance (var 0) ugly)
  (Inheritance (var 0) human))
```

The detail initializer also looks at the base atom's two argument slots once.
For:

```lisp
(Inheritance (var 0) ugly)
```

it records that the left base argument is a variable and the right base argument
is a constant. That becomes temporary left/right check facts.

After the cursor is exhausted, `ce-conjunct-var-check-fn` inspects the old
candidate atoms emitted by the scan. It marks `(var 0)` as a variable and
`human` as a constant. This tells the next scheduler which old-candidate values are valid connection
points.

Finally, `ce-base-shape-fn` combines the base-left and base-right checks into a
single `ce-base-shape` fact. Later map-building rules read that shape to decide
whether to use a two-variable, left-variable-only, or right-variable-only
mapping rule.

### Lines 202-218: `ce-schedule-choice-build-fn`

This scheduler decides what a variable in the base atom is allowed to become in
the expanded candidate.

The first scheduled rule, `ce-existing-choice-fn`, takes every variable found in
the old candidate and turns it into an `existing` choice. In the running example,
the old candidate has one variable:

```lisp
(var 0)
```

So it creates a choice meaning:

```lisp
(ce-var-choice ... (var 0) existing)
```

That choice is important because using an existing variable is what makes a new
base atom connected to the old candidate.

The second scheduled rule, `ce-drop-non-var-fn`, removes old-candidate constants
from the choice-building stream. For example, `human` appeared in the old atom,
but the base variable should not be mapped to the constant `human` by this
choice mechanism.

The next three scheduled rules work together to find the one fresh variable.
`ce-fresh-candidate-fn` proposes successors of existing variables. If the old
candidate contains `(var 0)`, it proposes `(var 1)`. If the old candidate
contains `(var 0)` and `(var 1)`, it can propose `(var 1)` and `(var 2)`.
`ce-drop-existing-fresh-fn` removes proposals that are already existing
variables, and `ce-save-fresh-choice-fn` saves the remaining proposal as a
`fresh` choice.

After this scheduler runs for the running example, a base variable has these
possible destinations:

```text
(var 0) existing
(var 1) fresh
```

The last two scheduled rules handle bases with two variable slots. For a base
like `(Inheritance (var 0) (var 1))`, the code must know whether those two slots
came from the same source variable or from different source variables.
`ce-base-source-indices-to-i32-fn` converts the source indices to comparable
integer values, then `ce-base-source-relation-fn` records either
`ce-base-source-same ... true` or `ce-base-source-same ... false`.

That distinction matters because `(P (var 0) (var 0))` must map both output
positions to the same selected variable, while `(P (var 0) (var 1))` can map the
left and right positions independently.

### Lines 221-237: `ce-schedule-map-build-fn`

This scheduler turns the choices from the previous step into actual base-atom
argument mappings, then filters those mappings by connectedness.

Different base shapes need different mapping rules.

If both base arguments came from the same source variable, such as:

```lisp
(P (var 0) (var 0))
```

then `ce-build-same-var-map-fn` creates maps where both output positions receive
the same selected choice. It preserves the repeated-variable meaning of the
base.

If both base arguments are variables but came from different source variables,
such as:

```lisp
(P (var 0) (var 1))
```

then `ce-build-distinct-var-map-fn` creates the cross product of left choices
and right choices. With choices `(var 0) existing` and `(var 1) fresh`, it can
create maps such as existing-existing, existing-fresh, fresh-existing, and
fresh-fresh.

If only the left side of the base is variable, `ce-build-left-var-map-fn` maps
the left side and leaves the right constant untouched. In the running example:

```lisp
(Inheritance (var 0) ugly)
```

it creates possible maps like:

```lisp
(Inheritance (var 0) ugly)  ; left uses existing variable
(Inheritance (var 1) ugly)  ; left uses fresh variable
```

If only the right side of the base is variable, `ce-build-right-var-map-fn` does
the mirror operation: the left constant stays unchanged and only the right side
is mapped.

After possible maps exist, `ce-check-map-connectivity-fn` labels each one as
connected or disconnected. A map is connected when at least one mapped position
uses an `existing` variable. Existing variables came from the old candidate;
fresh variables and constants do not connect by themselves.

For the running example:

```lisp
(Inheritance (var 0) ugly)
```

is connected because `(var 0)` already exists in the old candidate. But:

```lisp
(Inheritance (var 1) ugly)
```

is disconnected because `(var 1)` is fresh and `ugly` is a constant.

Finally, `ce-connect-map-fn` keeps connected maps by turning them into
`ce-connected-map` facts, while `ce-drop-disconnected-map-fn` deletes the
disconnected ones.

### Lines 240-257: `ce-schedule-output-build-fn`

This scheduler turns connected maps into raw candidates and then cleans up the
temporary expansion state.

First, `ce-build-connected-base-fn` rebuilds a real base atom from a connected
map. For the running example, the connected map says the base's output arguments
should be `(var 0)` and `ugly`, so the rebuilt base is:

```lisp
(Inheritance (var 0) ugly)
```

Next, `ce-build-raw-candidate-fn` unions that connected base atom with the old
candidate. The old candidate:

```lisp
((Inheritance (var 0) human))
```

plus the connected base:

```lisp
(Inheritance (var 0) ugly)
```

becomes a raw candidate:

```lisp
((Inheritance (var 0) ugly)
 (Inheritance (var 0) human))
```

It is called raw because it has not yet been sorted or alpha-canonicalized. That
happens in the next major section, starting at line 661.

The remaining scheduled rules are cleanup rules, but each one cleans a specific
kind of temporary fact. `ce-cleanup-var-choice-fn` removes variable choices,
`ce-cleanup-base-shape-fn` removes base-shape facts, and
`ce-cleanup-source-relation-fn` removes repeated-source-variable facts.
`ce-cleanup-expand-pair-fn` removes any malformed non-triplet pair facts that
were not consumed by the detail initializer.

Finally, `ce-finish-expansion-fn` removes the active `ce-expand-todo`. That is
what marks this old candidate's expansion as finished.

### Lines 260-264: `ce-expand-pair-fn`

This pairs one expandable candidate with every normalized base pattern.

Input:

```lisp
(ce-expand-todo 1 ((Inheritance (var 0) human)))
(ce-base (Inheritance (var 0) ugly))
```

Output:

```lisp
(ce-expand-pair
  1
  ((Inheritance (var 0) human))
  (Inheritance (var 0) ugly))
```

This fact means:

```text
Try expanding this old candidate with this base atom.
```

### Lines 269-298: `ce-expand-pair-details-fn`

This function initializes dynamic inspection of one candidate/base pair. It
does not pattern-match the number of atoms in the old candidate.

For the running example, it creates:

```lisp
(ce-expand-pair-scan
  1
  ((Inheritance (var 0) human))
  (Inheritance (var 0) ugly)
  ((Inheritance (var 0) human)))
```

The first list is the original candidate identity. The final list is the part
that remains to be scanned. Keeping both values prevents cursor state for one
candidate or base from joining facts belonging to another expansion.

The function also checks the base's left and right arguments once:

```lisp
(Inheritance (var 0) ugly)
```

becomes:

```lisp
(ce-base-left-check ... 1)
(ce-base-right-check ... 0)
```

`1` means variable and `0` means constant. After creating the cursor and these
two checks, it removes the consumed `ce-expand-pair` fact.

### Lines 303-320: `ce-expand-pair-scan-fn`

This is the dynamic MM2 list walker. One call performs one small state
transition:

```text
remaining = (A B C D)
emit A
remaining = (B C D)
schedule the same rule again
```

The next calls emit `B`, `C`, and `D` in the same way. In code, `car-atom`
returns the head atom and `cdr-atom` returns the unprocessed tail. The rule
deletes the old cursor, stores the tail as the next cursor, and re-schedules its
own `DEF` template at the same scan stage.

For the one-atom running example, its first pass emits:

```lisp
(ce-conjunct-atom
  1
  ((Inheritance (var 0) human))
  (Inheritance (var 0) ugly)
  (Inheritance (var 0) human))
```

It also stores an empty tail and schedules one last pass. On that pass,
`car-atom` and `cdr-atom` have no result, so no atom and no new cursor are
created; the exhausted cursor is simply removed. The scan therefore stops by
data exhaustion, not by comparing against `1`, `2`, or `3`.

`depth-of-conjunct` still controls how far mining is allowed to grow. It is a
policy limit used by the candidate filter, not an implementation limit in this
scanner.

### Lines 324-346: `ce-conjunct-var-check-fn`

This checks the old candidate's atoms and records which arguments are existing
variables.

For:

```lisp
(Inheritance (var 0) human)
```

it creates:

```lisp
(ce-conjunct-var-check ... (var 0) 1)
(ce-conjunct-var-check ... human 0)
```

The variable `(var 0)` can be used as an existing connection point for the new
base. The constant `human` cannot.

### Lines 350-360: `ce-base-shape-fn`

This joins the two base checks into one compact shape fact.

For:

```lisp
(Inheritance (var 0) ugly)
```

it creates:

```lisp
(ce-base-shape
  1
  ((Inheritance (var 0) human))
  (Inheritance (var 0) ugly)
  1
  0)
```

The last two fields mean:

```text
left argument is variable
right argument is constant
```

Later mapping functions use those flags to know which positions can be replaced
and which constants must stay unchanged.

### Lines 363-369: `ce-existing-choice-fn`

This turns every old-candidate variable into an allowed `existing` choice.

From:

```lisp
(ce-conjunct-var-check ... (var 0) 1)
```

it creates:

```lisp
(ce-var-choice
  1
  ((Inheritance (var 0) human))
  (Inheritance (var 0) ugly)
  (var 0)
  existing)
```

Meaning:

```text
A base variable may be mapped to existing variable (var 0).
```

### Lines 371-376: `ce-drop-non-var-fn`

This removes `ce-conjunct-var-check` facts for constants.

For example:

```lisp
(ce-conjunct-var-check ... human 0)
```

is removed because constants from the old candidate are not mapping choices.

### Lines 381-393: `ce-fresh-candidate-fn`

This proposes fresh variables after existing variables.

For every existing indexed variable, it computes `index + 1` entirely with
MM2 grounded operations. Given:

```lisp
(ce-var-choice ... (var 0) existing)
```

it creates:

```lisp
(ce-fresh-candidate ... (var 1))
```

If the old candidate had `(var 0)` and `(var 1)`, this rule could first propose
`(var 1)` and `(var 2)`. The next function removes any proposal that is already
an existing variable, leaving only the next genuinely fresh variable.

The computation is:

```lisp
(i32_to_string
  (sum_i32
    (i32_from_string $index)
    (i32_one)))
```

There is no successor lookup table to extend. For existing variables
`(var 0)` through `(var 4)`, the rule proposes `(var 1)` through `(var 5)`;
collision removal leaves `(var 5)`.

### Lines 395-401: `ce-drop-existing-fresh-fn`

This rejects a proposed fresh variable if it is already an existing variable.

Example:

```lisp
old candidate variables = (var 0), (var 1)
fresh proposals         = (var 1), (var 2)
```

It drops `(var 1)` because it already exists. That leaves `(var 2)` as the true
fresh variable.

### Lines 403-408: `ce-save-fresh-choice-fn`

This turns the remaining fresh proposal into a real mapping choice.

For the running example:

```lisp
(ce-fresh-candidate ... (var 1))
```

becomes:

```lisp
(ce-var-choice
  1
  ((Inheritance (var 0) human))
  (Inheritance (var 0) ugly)
  (var 1)
  fresh)
```

Now the base variable has two possible output choices:

```text
(var 0) existing
(var 1) fresh
```

### Lines 413-437: `ce-base-source-indices-to-i32-fn`

This only applies when both base arguments are variables:

```lisp
($predicate (var $left-index) (var $right-index))
```

Example:

```lisp
(Inheritance (var 0) (var 1))
```

It converts both source indices from strings to i32 values so they can be
compared later:

```lisp
(ce-base-source-left-i32 ... <i32-0>)
(ce-base-source-right-i32 ... <i32-1>)
```

This matters for bases like:

```lisp
(Equal (var 0) (var 0))
```

Both positions came from the same source variable, so after mapping they must
still be equal.

### Lines 441-457: `ce-base-source-relation-fn`

This compares the two base source variable indices.

For:

```lisp
(Inheritance (var 0) (var 1))
```

it creates:

```lisp
(ce-base-source-same ... false)
```

For:

```lisp
(Equal (var 0) (var 0))
```

it creates:

```lisp
(ce-base-source-same ... true)
```

That fact decides whether the two output positions must share one mapping or
can take independent choices.

### Lines 460-466: `ce-build-same-var-map-fn`

This handles bases where both variable positions came from the same source
variable.

If the base is:

```lisp
(Equal (var 0) (var 0))
```

then both output positions must receive the same selected variable.

So a choice:

```lisp
(ce-var-choice ... (var 0) existing)
```

creates:

```lisp
(ce-base-var-map ... (var 0) existing (var 0) existing)
```

It does not produce mixed mappings like:

```lisp
(Equal (var 0) (var 1))
```

because that would break the repeated-variable meaning of the base.

### Lines 469-482: `ce-build-distinct-var-map-fn`

This handles bases where the left and right source variables are different.

For:

```lisp
(Inheritance (var 0) (var 1))
```

the left and right positions can independently choose any available output
choice.

If choices are:

```text
(var 0) existing
(var 1) fresh
```

then possible maps include:

```lisp
(ce-base-var-map ... (var 0) existing (var 0) existing)
(ce-base-var-map ... (var 0) existing (var 1) fresh)
(ce-base-var-map ... (var 1) fresh    (var 0) existing)
(ce-base-var-map ... (var 1) fresh    (var 1) fresh)
```

Connectivity filtering happens later.

### Lines 486-508: `ce-build-left-var-map-fn`

This handles a base where only the left argument is variable.

Running example:

```lisp
(Inheritance (var 0) ugly)
```

Shape:

```text
left variable, right constant
```

The right side must stay `ugly`. The left side can use each available variable
choice:

```lisp
(ce-base-var-map ... (var 0) existing ugly constant)
(ce-base-var-map ... (var 1) fresh    ugly constant)
```

### Lines 510-532: `ce-build-right-var-map-fn`

This is the mirror of `ce-build-left-var-map-fn`.

It handles bases like:

```lisp
(Inheritance human (var 0))
```

The left side stays `human`. The right side can use each available variable
choice:

```lisp
(ce-base-var-map ... human constant (var 0) existing)
(ce-base-var-map ... human constant (var 1) fresh)
```

### Lines 536-569: `ce-check-map-connectivity-fn`

This checks whether a mapping touches the old candidate.

The helper facts near the bottom of the source define:

```lisp
(ce-source-connectivity existing 1)
(ce-source-connectivity fresh 0)
(ce-source-connectivity constant 0)
```

So this rule says:

```text
connected = max(left-kind-connected, right-kind-connected)
```

Examples:

```text
existing + constant -> connected
fresh + constant    -> disconnected
fresh + fresh       -> disconnected
existing + fresh    -> connected
```

For the running example:

```lisp
(ce-base-var-map ... (var 0) existing ugly constant)
```

becomes connected:

```lisp
(ce-base-var-map-connectivity ... (var 0) ugly 1)
```

but:

```lisp
(ce-base-var-map ... (var 1) fresh ugly constant)
```

becomes disconnected:

```lisp
(ce-base-var-map-connectivity ... (var 1) ugly 0)
```

### Lines 571-579: `ce-connect-map-fn`

This keeps maps with connectivity `1`.

For the running example, it keeps:

```lisp
(ce-connected-map
  1
  ((Inheritance (var 0) human))
  (Inheritance (var 0) ugly)
  (var 0)
  ugly)
```

This means:

```text
The base can be rebuilt as (Inheritance (var 0) ugly).
```

### Lines 581-587: `ce-drop-disconnected-map-fn`

This removes maps with connectivity `0`.

For the running example, it drops:

```lisp
(Inheritance (var 1) ugly)
```

Why? Because `(var 1)` would be fresh and the other position is a constant, so
the new atom would not share any variable with the old candidate.

### Lines 590-608: `ce-build-connected-base-fn`

This rebuilds the base atom from a connected map.

From:

```lisp
(ce-connected-map
  1
  ((Inheritance (var 0) human))
  (Inheritance (var 0) ugly)
  (var 0)
  ugly)
```

it creates:

```lisp
(ce-connected-base
  1
  ((Inheritance (var 0) human))
  (Inheritance (var 0) ugly))
```

At this point the system has a base variant that is safe to union with the old
candidate.

### Lines 612-621: `ce-build-raw-candidate-fn`

This unions the connected base variant with the old candidate.

The key call is:

```lisp
(union-atom (' (($connected-base) $conjunct)))
```

For the running example, it creates:

```lisp
(ce-raw-candidate
  1
  ((Inheritance (var 0) ugly)
   (Inheritance (var 0) human)))
```

The order is not final. The canonicalization stage sorts it later.

`union-atom` also prevents duplicate atoms from increasing the size. If the
connected base is already inside the old candidate, the candidate stays the same
size and the later growth check rejects it.

### Lines 625-630: `ce-cleanup-var-choice-fn`

This removes leftover `ce-var-choice` facts for the active expansion.

Those facts are temporary. If they were left around, a later candidate could
accidentally reuse choices from this candidate.

### Lines 632-638: `ce-cleanup-base-shape-fn`

This removes leftover `ce-base-shape` facts.

These facts are also pair-scoped: they describe one old candidate with one base
pattern.

### Lines 640-645: `ce-cleanup-source-relation-fn`

This removes leftover `ce-base-source-same` facts.

That prevents repeated-variable information for one base from leaking into
another expansion.

### Lines 649-653: `ce-cleanup-expand-pair-fn`

This removes any remaining `ce-expand-pair` facts.

Normally valid triplet pairs are already consumed by
`ce-expand-pair-details-fn`. This cleanup catches malformed or non-triplet
pairs.

### Lines 655-658: `ce-finish-expansion-fn`

This removes the active `ce-expand-todo` fact.

That is the final cleanup step for one old candidate's expansion. After this,
the raw candidates produced by the expansion continue into the canonicalization
pipeline starting at line 661.

## Lines 661-690: Candidate Canonicalization

Candidate canonicalization now has three explicit stages.

### Lines 661-668: `ce-sort-candidate-fn`

First, the raw candidate is sorted:

```lisp
(DEF ce-sort-candidate-fn
    (, (ce-raw-candidate $old-size $raw))
    (O
        (pure
            (ce-sorted-candidate $old-size $sorted)
            $sorted
            (sort-atom (' $raw)))
        (- (ce-raw-candidate $old-size $raw))))
```

Example raw candidate:

```lisp
((Inheritance (var 0) ugly)
 (Inheritance (var 0) human))
```

After sorting, it might become:

```lisp
((Inheritance (var 0) human)
 (Inheritance (var 0) ugly))
```

This collapses candidates that differ only by conjunct order.

### Lines 672-679: `ce-candidate-to-vars-fn`

Next, the sorted indexed candidate is converted back to real MM2 variables:

```lisp
(indices_to_vars (' $sorted))
```

Example:

```lisp
((Parent (var 0) (var 2))
 (Inheritance (var 0) (var 1)))
```

becomes conceptually:

```lisp
((Parent $a $b)
 (Inheritance $a $c))
```

The exact variable names are not important. What matters is the equality
structure.

### Lines 683-690: `ce-alpha-candidate-fn`

Finally, the real-variable form is converted back to indexed form:

```lisp
(vars_to_indices (' $as-vars))
```

That reassigns variable indices by first occurrence after sorting.

So these two sorted candidates:

```lisp
((Parent (var 0) (var 1))
 (Inheritance (var 0) (var 2)))
```

```lisp
((Parent (var 0) (var 2))
 (Inheritance (var 0) (var 1)))
```

both become:

```lisp
(ce-candidate $old-size
  ((Parent (var 0) (var 1))
   (Inheritance (var 0) (var 2))))
```

That is how alpha-equivalent duplicate conjunctions are removed without adding a
Rust helper.

## Lines 693-700: `ce-candidate-size-fn`

Source:

```lisp
(DEF ce-candidate-size-fn
    (, (ce-candidate $old-size $candidate))
    (O
        (pure
            (ce-candidate-size $old-size $candidate $size)
            $size
            (size-atom (' $candidate)))
        (- (ce-candidate $old-size $candidate))))
```

This counts how many conjuncts are inside the candidate.

Example:

```lisp
((Inheritance (var 0) human)
 (Inheritance (var 0) ugly))
```

has size:

```text
2
```

So it creates:

```lisp
(ce-candidate-size 1
  ((Inheritance (var 0) human)
   (Inheritance (var 0) ugly))
  2)
```

The `1` is the old size. The `2` is the new size.

Then it removes:

```lisp
(ce-candidate ...)
```

because the candidate is now represented by `ce-candidate-size`.

## Lines 703-713: `ce-candidate-size-to-i32-fn`

Source:

```lisp
(DEF ce-candidate-size-to-i32-fn
    (, (ce-candidate-size $old-size $candidate $size))
    (O
        (pure
            (ce-candidate-size-i32 $candidate $size $size-i32)
            $size-i32
            (i32_from_string $size))
        (pure
            (ce-candidate-old-size-i32 $candidate $size $old-size-i32)
            $old-size-i32
            (i32_from_string $old-size))))
```

This converts both sizes into integer values.

Example input:

```lisp
(ce-candidate-size 1
  ((Inheritance (var 0) human)
   (Inheritance (var 0) ugly))
  2)
```

It creates:

```lisp
(ce-candidate-size-i32
  ((Inheritance (var 0) human)
   (Inheritance (var 0) ugly))
  2
  <binary-i32-2>)
```

and:

```lisp
(ce-candidate-old-size-i32
  ((Inheritance (var 0) human)
   (Inheritance (var 0) ugly))
  2
  <binary-i32-1>)
```

The second fact stores old size `1`, but it uses the new size `2` as part of
the fact key so it can join with the matching new-size fact in the next stage.

## Lines 716-732: `ce-candidate-pass-fn`

Source:

```lisp
(DEF ce-candidate-pass-fn
    (, (ce-candidate-size $old-size $candidate $size)
       (ce-candidate-size-i32 $candidate $size $size-i32)
       (ce-candidate-old-size-i32 $candidate $size $old-size-i32)
       (ce-max-depth-i32 $max-depth $max-depth-i32))
    (O
        (pure
            (ce-candidate-depth-pass $candidate $size $pass)
            $pass
            (le_i32 $size-i32 $max-depth-i32))
        (pure
            (ce-candidate-growth-pass $candidate $size $growth-pass)
            $growth-pass
            (gt_i32 $size-i32 $old-size-i32))
        (- (ce-candidate-size $old-size $candidate $size))
        (- (ce-candidate-size-i32 $candidate $size $size-i32))
        (- (ce-candidate-old-size-i32 $candidate $size $old-size-i32))))
```

This checks two things.

First:

```text
new size <= max depth
```

For our example:

```text
2 <= 3 = true
```

So it creates:

```lisp
(ce-candidate-depth-pass
  ((Inheritance (var 0) human)
   (Inheritance (var 0) ugly))
  2
  true)
```

Second:

```text
new size > old size
```

For our example:

```text
2 > 1 = true
```

So it creates:

```lisp
(ce-candidate-growth-pass
  ((Inheritance (var 0) human)
   (Inheritance (var 0) ugly))
  2
  true)
```

Now compare that with the duplicate-add case:

```text
old candidate = human
base = human
```

`union-atom` keeps the result as:

```text
human
```

So:

```text
new size = 1
old size = 1
1 > 1 = false
```

That candidate gets a growth pass of `false`, so it will not be queued.

## Lines 735-743: `ce-queue-candidate-fn`

Source:

```lisp
(DEF ce-queue-candidate-fn
    (, (ce-candidate-depth-pass $candidate $size true)
       (ce-candidate-growth-pass $candidate $size true)
       (DEF ce-support-fn $support-p $support-t))
    (O
        (+ (ce-pending $size $candidate))
        (+ (exec (CE 1 0) $support-p $support-t))
        (- (ce-candidate-depth-pass $candidate $size true))
        (- (ce-candidate-growth-pass $candidate $size true))))
```

This only runs when both checks are true:

```text
depth pass = true
growth pass = true
```

Example:

```lisp
(ce-candidate-depth-pass HUMAN-UGLY 2 true)
(ce-candidate-growth-pass HUMAN-UGLY 2 true)
```

It adds:

```lisp
(ce-pending 2 HUMAN-UGLY)
```

Meaning:

```text
Now count support for the size-2 candidate.
```

It also schedules:

```lisp
(exec (CE 1 0) $support-p $support-t)
```

That restarts the support-count cycle for this new candidate.

Then it removes the two pass facts.

## Lines 746-751: `ce-drop-candidate-fn`

Source:

```lisp
(DEF ce-drop-candidate-fn
    (, (ce-candidate-depth-pass $candidate $size $depth-pass)
       (ce-candidate-growth-pass $candidate $size $growth-pass))
    (O
        (- (ce-candidate-depth-pass $candidate $size $depth-pass))
        (- (ce-candidate-growth-pass $candidate $size $growth-pass))))
```

This cleans up candidates that did not pass both checks.

Example 1: duplicate candidate did not grow.

```lisp
(ce-candidate-depth-pass HUMAN 1 true)
(ce-candidate-growth-pass HUMAN 1 false)
```

The function removes both facts.

Example 2: candidate is too deep.

```lisp
(ce-candidate-depth-pass SIZE-4-CANDIDATE 4 false)
(ce-candidate-growth-pass SIZE-4-CANDIDATE 4 true)
```

The function removes both facts.

Nothing is queued.

## Lines 757-776: Configuration Metadata And Pipeline

Before the first `exec`, the source defines how each output-position kind
contributes to connectedness:

```lisp
(ce-source-connectivity existing 1)
(ce-source-connectivity fresh 0)
(ce-source-connectivity constant 0)
```

Then it converts the threshold and depth settings once.

Source:

```lisp
(exec (CE 0 0)
    (, (support-threshold $threshold)
       (depth-of-conjunct $max-depth))
    (O
        (pure
            (ce-threshold-i32 $threshold $threshold-i32)
            $threshold-i32
            (i32_from_string $threshold))
        (pure
            (ce-max-depth-i32 $max-depth $max-depth-i32)
            $max-depth-i32
            (i32_from_string $max-depth))))
```

With the demo input:

```lisp
(support-threshold 2)
(depth-of-conjunct 3)
```

it creates:

```lisp
(ce-threshold-i32 2 <binary-i32-2>)
(ce-max-depth-i32 3 <binary-i32-3>)
```

The value `3` is only the demo's configured stopping point. It can be replaced
with a larger depth without adding extractor rules or variable-successor facts;
the cursor and arithmetic fresh-variable generation are independent of this
number. The implementation remains triplet-only in atom shape, but conjunction
length is dynamic.

These facts are used later by:

```text
support comparison
depth comparison
candidate size comparison
```

## Lines 780-787: Seed Pipeline

Current source:

```lisp
(exec (CE 0 1)
    (, (pattern 0 $pattern))
    (O
        (pure
            (exec (0 0) (,) (O (+ (ce-base $indexed)) (+ (ce-pending 1 ($indexed)))))
            $indexed
            (vars_to_indices (' $pattern))
        )))
```

This runs once for each input pattern.

Example pattern:

```lisp
(pattern 0 (Inheritance $x human))
```

The helper call:

```lisp
(vars_to_indices (' $pattern))
```

turns:

```lisp
(Inheritance $x human)
```

into:

```lisp
(Inheritance (var 0) human)
```

Then the generated output adds:

```lisp
(ce-base (Inheritance (var 0) human))
(ce-pending 1 ((Inheritance (var 0) human)))
```

For all four demo patterns, the intended seed facts are:

```lisp
(ce-base (Inheritance (var 0) human))
(ce-base (Inheritance (var 0) (var 1)))
(ce-base (Inheritance (var 0) ugly))
(ce-base (Inheritance (var 0) sodaDrinker))
```

and:

```lisp
(ce-pending 1 ((Inheritance (var 0) human)))
(ce-pending 1 ((Inheritance (var 0) (var 1))))
(ce-pending 1 ((Inheritance (var 0) ugly)))
(ce-pending 1 ((Inheritance (var 0) sodaDrinker)))
```

Note: this seed rule is written in a compact generated-`exec` style. Its
purpose is still simple: make every input pattern a base pattern and a size-1
candidate waiting for counting.

## Lines 790-793: Start The First Support Cycle

Source:

```lisp
(exec (CE 0 2)
    (, (DEF ce-support-fn $support-p $support-t))
    (O
        (+ (exec (CE 1 0) $support-p $support-t))))
```

This schedules the first `ce-support-fn` execution.

In plain English:

```text
Now that base candidates exist, start counting pending candidates.
```

The first pending candidate might be:

```lisp
(ce-pending 1 ((Inheritance (var 0) human)))
```

That candidate goes into `ce-support-fn`, and the loop begins.

## Full Walkthrough: Human Pattern

Start:

```lisp
(pattern 0 (Inheritance $x human))
```

Seed stage creates:

```lisp
(ce-base (Inheritance (var 0) human))
(ce-pending 1 ((Inheritance (var 0) human)))
```

Support stage converts pending candidate to query:

```lisp
(, (Inheritance $x human))
```

Count result:

```lisp
(ce-support 1 ((Inheritance (var 0) human)) 4)
```

Convert support:

```lisp
(ce-support-i32 1 ((Inheritance (var 0) human)) 4 <binary-i32-4>)
```

Compare with threshold:

```text
4 >= 2 = true
```

Pass fact:

```lisp
(ce-support-pass 1 ((Inheritance (var 0) human)) 4 true)
```

Save output:

```lisp
(expanded-conjunct 1 ((Inheritance (var 0) human)) 4)
```

Check depth:

```text
1 < 3 = true
```

Expansion todo:

```lisp
(ce-expand-todo 1 ((Inheritance (var 0) human)))
```

Then this candidate is combined with every `ce-base`.

## Full Walkthrough: Human + Ugly

One expansion combines:

```lisp
(ce-expand-todo 1 ((Inheritance (var 0) human)))
```

with:

```lisp
(ce-base (Inheritance (var 0) ugly))
```

Build raw candidate:

```lisp
(ce-raw-candidate 1
  ((Inheritance (var 0) ugly)
   (Inheritance (var 0) human)))
```

Sort candidate:

```lisp
(ce-sorted-candidate 1
  ((Inheritance (var 0) human)
   (Inheritance (var 0) ugly)))
```

Convert to real variables for alpha-normalization:

```lisp
(ce-candidate-vars 1
  ((Inheritance $a human)
   (Inheritance $a ugly)))
```

Re-index variables into the final canonical candidate:

```lisp
(ce-candidate 1
  ((Inheritance (var 0) human)
   (Inheritance (var 0) ugly)))
```

Compute size:

```lisp
(ce-candidate-size 1
  ((Inheritance (var 0) human)
   (Inheritance (var 0) ugly))
  2)
```

Check depth:

```text
2 <= 3 = true
```

Check growth:

```text
2 > 1 = true
```

Queue candidate:

```lisp
(ce-pending 2
  ((Inheritance (var 0) human)
   (Inheritance (var 0) ugly)))
```

Support query:

```lisp
(,
  (Inheritance $x human)
  (Inheritance $x ugly))
```

Matches:

```text
Allen, Bob, Dana
```

Support:

```text
3
```

Output:

```lisp
(expanded-conjunct 2
  ((Inheritance (var 0) human)
   (Inheritance (var 0) ugly))
  3)
```

Since:

```text
2 < 3
```

it can expand one more time.

## Full Walkthrough: Human + Ugly + SodaDrinker

The size-2 candidate:

```lisp
((Inheritance (var 0) human)
 (Inheritance (var 0) ugly))
```

combines with:

```lisp
(Inheritance (var 0) sodaDrinker)
```

Candidate:

```lisp
((Inheritance (var 0) human)
 (Inheritance (var 0) sodaDrinker)
 (Inheritance (var 0) ugly))
```

After sorting and re-indexing, it gets one stable canonical shape.

Size:

```text
3
```

Depth check during candidate creation:

```text
3 <= 3 = true
```

Growth check:

```text
3 > 2 = true
```

So it is queued and counted.

Support query:

```lisp
(,
  (Inheritance $x human)
  (Inheritance $x ugly)
  (Inheritance $x sodaDrinker))
```

Matches:

```text
Allen, Dana
```

Support:

```text
2
```

Threshold check:

```text
2 >= 2 = true
```

Output:

```lisp
(expanded-conjunct 3
  ((Inheritance (var 0) human)
   (Inheritance (var 0) sodaDrinker)
   (Inheritance (var 0) ugly))
  2)
```

Then expansion check:

```text
3 < 3 = false
```

So it stops here.

## Full Walkthrough: Duplicate Add

Start with:

```lisp
(ce-expand-todo 1 ((Inheritance (var 0) human)))
```

Combine with the same base:

```lisp
(ce-base (Inheritance (var 0) human))
```

`union-atom` keeps only one copy:

```lisp
((Inheritance (var 0) human))
```

Size:

```text
1
```

Old size:

```text
1
```

Growth check:

```text
1 > 1 = false
```

So this candidate is dropped. It is not counted again.

## Full Walkthrough: Why Sorting Avoids Repeated Work

The miner can build human+ugly in two ways.

Way 1:

```text
start with human, add ugly
```

Raw:

```lisp
((Inheritance (var 0) ugly)
 (Inheritance (var 0) human))
```

Way 2:

```text
start with ugly, add human
```

Raw:

```lisp
((Inheritance (var 0) human)
 (Inheritance (var 0) ugly))
```

Without sorting, those are different data shapes even though they mean the same
logical query.

With sorting, both get the same atom order:

```lisp
((Inheritance (var 0) human)
 (Inheritance (var 0) ugly))
```

Then alpha-normalization removes duplicate shapes that only differ by variable
numbering.

Example:

```lisp
((Parent (var 0) (var 1))
 (Inheritance (var 0) (var 2)))
```

and:

```lisp
((Parent (var 0) (var 2))
 (Inheritance (var 0) (var 1)))
```

become the same `ce-candidate` after:

```text
sort-atom -> indices_to_vars -> vars_to_indices
```

So the system has one canonical form for order duplicates and alpha-equivalent
variable-numbering duplicates.

## Full Walkthrough: A Candidate That Fails Support

Imagine the miner builds a candidate that only matches one database entity.

Example:

```lisp
(,
  (Inheritance $x ugly)
  (Inheritance $x sodaDrinker)
  (Inheritance $x someRareThing))
```

Suppose support is:

```text
1
```

Then:

```text
1 >= 2 = false
```

The code creates:

```lisp
(ce-support-pass SOME-CANDIDATE 1 false)
```

Then `ce-drop-fail-fn` removes it.

No `expanded-conjunct` is created.
No `ce-expand-check` is created.
No larger candidates are built from it.

## What Each Main Fact Means

| Fact | When it appears | What it means |
|---|---|---|
| `ce-base` | Seed stage | A single normalized pattern that can be added to candidates |
| `ce-pending` | Seed or queue stage | A candidate waiting to be counted |
| `ce-support` | Count stage | A candidate was counted |
| `ce-support-i32` | Conversion stage | Support is ready for numeric comparison |
| `ce-support-pass` | Threshold stage | Candidate passed or failed support threshold |
| `ce-conjunct` | Save stage | Candidate is frequent |
| `expanded-conjunct` | Save stage | Main output fact |
| `ce-expand-check` | Save stage | Candidate should be checked for further expansion |
| `ce-expand-size-i32` | Depth setup | Candidate size is ready for numeric comparison |
| `ce-expand-pass` | Depth check | Candidate can or cannot expand further |
| `ce-expand-todo` | Expansion queue | Candidate will be combined with base patterns |
| `ce-connected-map` | Expansion stage | A base-variable map that touches the old candidate |
| `ce-connected-base` | Expansion stage | A base pattern after applying a connected map |
| `ce-raw-candidate` | Build stage | Candidate before canonicalization |
| `ce-sorted-candidate` | Canonical stage | Candidate after atom-order sorting |
| `ce-candidate-vars` | Canonical stage | Sorted candidate temporarily converted to real MM2 variables |
| `ce-candidate` | Canonical stage | Candidate after sorting and alpha-normalized re-indexing |
| `ce-candidate-size` | Size stage | Candidate with its new size |
| `ce-candidate-depth-pass` | Candidate filter | New candidate is or is not within max depth |
| `ce-candidate-growth-pass` | Candidate filter | New candidate did or did not actually grow |

## The Whole File In One Concrete Loop

Using the demo input, the loop is:

```text
pattern human
  -> ce-base human
  -> ce-pending human
  -> count human = 4
  -> 4 >= 2, save human
  -> 1 < 3, expand human
  -> build human+ugly, human+sodaDrinker, human+($y), duplicate human
  -> drop duplicate human
  -> count real size-2 candidates
  -> save candidates with support >= 2
  -> expand size-2 candidates
  -> build size-3 candidates
  -> count them
  -> save those with support >= 2
  -> stop because size 3 is max depth
```

That is the whole algorithm.
