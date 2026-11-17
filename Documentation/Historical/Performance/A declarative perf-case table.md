# A declarative perf-case table: hundreds of cases, counted in the gate, timed on demand

*A design, written 2026-11-14 against `main` at 750e1de04, in answer to the owner's question of
the same day: there are still a lot of situations nobody has profiled, so should they become more
`Stress` scenarios, or does a framework with hundreds of cases to cover need a better way to
state a performance test? Nothing here is built. Ids: A-PERFCASE-1 to 3 (for the owner),
B-PERFCASE-1 to 7 (decided here).*

## In short

Keep `Stress`, and stop writing a scenario per case. A case becomes **one line in a table**: a
composition (what the page is built from), the container it sits in, a terminal size, a data
count, an interaction script, a scaling class, whether it is timed, and tags. The vocabulary
behind those columns is a handful of Swift enums in `Stress`, written once. A case with a script
runs as a `Stress` session, through one generic `StressSession`. A case without one runs as a
variant of one matrix scenario. Every tool that already reads scenarios, variants and sessions
off the binary (`--selfcheck`, `ab_bench.py`, `ab_counters.py`, `sweep.py`, `frame_parity.py`)
picks the cases up without changes.

Every case is **counted** in the gate: rows built and served, bodies run (a new counter), cell
values, measure-memo misses and bytes written, per phase of its script, compared with a recorded
file. A count that moves fails the gate until the commit re-records it and says why. Counts are
deterministic, cost milliseconds and need no quiet machine, so hundreds of cases can be checked on
every landing. Only cases marked `timed` (a few dozen) go into `ab_bench.py`'s sweep, which stays
on demand, because each timed case costs about 90 s of a quiet machine.

Five lanes, about 8 to 10 lane-days. The ten example cases below are the first rows.

## The problem

### What the owner asked (2026-11-14)

"There's still a *lot* of situations that haven't been profiled. I don't know if it makes sense to
add heaps more cases to Stress (it is an internal tool, so there's no real issue with doing that)
or if we need a better way to express performance tests when we have potentially hundreds of
cases we want to cover?"

### What `Stress` does well

`Stress` ([its README](<../../../Sources/Stress/README.md>)) has had 192 commits since 2026-07-19,
and most of what it has learned is worth keeping:

- **Determinism without data on disk.** Every data set is synthesised from a seed (`Synth.swift`),
  so a million-row list costs O(1) memory, and two runs of one build draw the same frames.
- **The real pipeline.** `--bench` runs the render loop's per-pass lifecycle around each frame,
  rooted at a type as an app is. Sessions drive the real `HeadlessApp`, with its five-layer input
  chain, header, status bar and diff writer, on a clock the runner supplies.
- **Oracles that need no expected pictures.** `--selfcheck` draws every scenario, variant and
  session in CI, memo-verified. `--verify` plays a script against a twin whose render cache is
  emptied before every frame. `check(_:after:)` judges what a page must show from the model it
  drives. `--frame-checksums` with `frame_parity.py` says whether two builds draw alike.
- **Counts beside times.** `memos/frame`, `rows/frame`, bytes per step kind, the observation
  census and, with `--allocs`, allocations. `ab_counters.py` compares them across two builds on a
  busy machine.
- **An A/B that says "cannot tell".** `ab_bench.py` reads thread CPU time, randomises run order,
  pairs ratios, bootstraps an interval and calibrates each run to 4.5 s. Its null tests are
  recorded ([Profiling README](<../../../Tools/Profiling/README.md>)).
- **Matrices.** A variant is one literal in a `*Variants.swift` file, with no registry entry and
  no translation (`ScenarioVariant`). `app-shapes` found costs that no single-purpose fixture
  could, for example `chat` against `chat-eager`: 1.4 ms against 189 ms for the same application.

### Where it does not scale

**The cost of a new case.** There are 38 registered scenarios, about a hundred variants (by a
count of their literals) and about two dozen sessions. Each costs differently:

| Unit | What one costs | Translation |
|---|---|---|
| Scenario | A Swift file (`WideFanout.swift` is 80 lines), a registry entry, three strings | Three keys in each of eight string tables, checked by a parity test |
| Variant | A closure literal that builds a view by hand | None |
| Session | A class implementing `StressSession` (`JobsSession.swift` is 212 lines), with its own model, script and checks | None |

A variant is cheap, but it names its point in the space by hand. Nothing takes a cross product,
so "the same list, but in a sheet, at 40 by 12, while typing" is a new closure or a new session,
not a new line.

**The axes are flags, not part of a case.** Terminal size is `--cols`/`--rows`, and the data
count is `--scale`, a multiplier whose meaning differs from one scenario to the next. Both are
chosen at run time, so a case is never recorded at a size. `frame_parity.py`'s documentation has
to remind its reader to "try `--cols`/`--rows` too: a narrow terminal takes other paths".
Interaction exists only in sessions, and every session is written by hand.

**Picking the cases for an A/B is done by hand each time.** The landing stream's working notes
hold 30 `ab_*.sh` scripts, and each one hard-codes its own subset
(`S="megalist scrollfollow scrolleager kitchensink controls table"`). Whether that subset covers
what a change touched is a judgement made fresh each time. The one time the list itself was
hard-coded, in `ab_bench.py`, `menus` and `gradients` were missing from every "full sweep" for
weeks.

**Timing is the scarce resource, and the sweep is already an hour.** Each timed case costs
4.5 s × 10 reps × 2 binaries, about 90 s. The full sweep of the scenarios is about an hour.
Timing every variant and session the same way would take about four hours, and 300 cases about
seven and a half. Many cases do not need a clock at all: "does this list build only the rows it
shows" is a count, and asking a stopwatch the question wastes the quiet machine on it.

**Nothing fails.** `ab_counters.py` is, in its own words, "an A/B tool, not a gate". A count that
doubles is seen only if someone runs it on that commit. Sweep results live in the working notes,
and nothing compares them across commits.

**Counting tests exist, but each one is hand-rolled.** `PulledListTests` has its own `Builds`
class and the bound `< 100`. `TableInScrollViewHeightTests` has a `BuiltCells` class and the bounds
`< 500` and `< 200`. Nothing counts body runs, so `ab_counters.py` notes that it "has no count of
body runs". The counter-example is `ScrollFitBaselineTests`: 28 subjects × 5 situations × 2 row
counts, 280 cases in a 286-line text table checked by one parameterised test, each case one line.
It records sizes, not work, but it is the shape this design borrows.

## Options

### 1. More `Stress` scenarios, variants and sessions

No new machinery. But the cost per case stays linear and hand-written, the axes stay implicit,
the sweep grows with every case, and nothing fails. It is the right home for a shape worth a name
(`deep`, `gradients`), and the wrong unit for a space of hundreds of points. This is the
conclusion `ScenarioVariant` reached for one API, applied to all of them.

### 2. A declarative table of cases

A case is a row: composition × container × size × count × script. The harness builds and runs
it, and the vocabulary is written once. The open question is where the vocabulary and the runner
live:

- **(a) in `Stress`.** `Synth`, the session runner, the matrix registry and the bench already live
  there, and the gate already runs `Stress --selfcheck` (in debug, on macOS and on CI's Linux
  lanes). No new target. The counts are checked by a new `Stress --check-counts`, which is serial,
  without Swift Testing's per-case reporting.
- **(b) in a new library target** shared by `Stress` and a test target, run as a parameterised
  Swift Testing test. This gives per-case failures and `--filter`, but adds a target to the build
  graph that the owner pays compile time for, and moves `Synth` out of `Stress`.

(a) is recommended (B-PERFCASE-3). (b) remains open if the serial check grows past its budget.

### 3. Work-count budgets as checks

Counts are deterministic: the same build and script do the same work on any machine, loaded or
not, in debug as in release. `HeadlessApp` already turns off the one memo that learns from timing
(`learnsFromTiming = false`). They are cheap, and they answer the questions most of this
framework's performance history turned on:

- O(visible) or O(n): the rows built at n and at 10n;
- whether a memo serves: rows served and memo misses;
- what an edit invalidates: rows rebuilt after one write;
- what a keystroke costs the terminal: bytes per step.

`.fit`'s O(rows) scan and the wrapped table's 256-row cliff were found in `sweep.py` as one row
costing several times its neighbours. Each was also a count, and the cliff was first stated as one:
828 cell values for 12 drawn rows, 69 per row. A count would have shown either as plainly, on any
machine.

Counts have a known blind spot, which this design keeps in view. The 2026-08 copying accumulator
in `FrameBuffer.appendVertically` made every stack O(n²) in time while `measureChild` calls stayed
linear: 14,409 / 28,809 / 75,212 / 150,412 for 2k to 16k children. No call count saw it. An
allocation count would have (it is how the `Array` copy-on-write defeat of 2026-09-17 was
pinned), but allocation counts are macOS-only and move by about 1% between runs, so they stay in
`ab_counters.py` and out of the gate. Constant factors, such as one `Int` field in `RenderContext`
costing 2.4%, are also invisible to counts. Timing stays.

### 4. Wall-time A/Bs

Unchanged in method: `ab_bench.py` is right for what it does. What changes is what it is pointed
at. The default sweep becomes the cases marked `timed`, read off the binary, and `--tags` picks a
subset by tag instead of by a hand-written `S="…"`.

### 5. Trend tracking across commits

For counts, the recorded file's own git history is the trend. Every change to it is a commit that
says why, so `git log -p` on the file reads as a ledger of what each change did to each case, at
no cost to the repository beyond a text file. For times, a sweep of the `timed` cases appends one
CSV row per case (commit, toolchain, machine, load, µs, interval) to the working notes, never to
the repository (the same rule as `.trace` bundles). A small script flags a case that has drifted
past its noise floor against the median of its last five readings. Whether to keep the timing
trend at all is A-PERFCASE-3.

### Choosing between counting and timing for a case

Every case is counted, because counting costs nothing worth arguing over. A case is also
**timed** when at least one of these holds:

| Reason to time | Example |
|---|---|
| Its cost is in work no counter sees: per-glyph drawing, compositing, colour arithmetic, emission | `gradients`, `translucent`, `alpharamp`, `texteffects` |
| It stands for a class of application, and constant factors there are what a user feels | `app-shapes` variants, sessions such as `notes` and `settings` |
| It was the site of a regression that counts did not show | the stacks that the copying accumulator hit (`fanout`, `modifiers`) |
| It is half of a measured pair | `chat` / `chat-eager`, `code-editor` / `code-editor-tailing` |

A case that is only asking about complexity class, memo serving or invalidation is not timed. The
timed set is kept to the size of a sweep of about an hour: 40 cases at 90 s each.

## Recommendation

### The schema

Each row has these columns, separated by runs of spaces as in `ScrollFitBaselineTable.swift`.
Spaces may not appear inside a column.

| Column | Meaning | Values |
|---|---|---|
| `id` | Stable, kebab-case; the session or variant id is `case:<id>` | unique |
| `composition` | What the page is built from: a name from `CaseComposition`, with dotted options | `list.plain`, `list.search`, `table.fit5`, `table.wrap5`, `chat.lazy`, `chat.eager`, `editor.wrap`, `tabs(list.plain,table.fit5)`, `split(list.plain,table.fit5)`, `follows(list.plain)` (in a scene whose focus follows the pointer; added 2026-11-16), … ; `stress:<scenario>[/<variant>]` adopts an existing one |
| `in` | The container around it: `CaseContainer`, a superset of `ScrollFitSituation` | `alone`, `title` (in a `ScrollView` under a title), `bottom` (bottom-anchored `ScrollView`), `sheet`, `fixed`, `stacked` (under a title in a `VStack` that fills the page), `-` for an adopted scenario |
| `size` | The terminal, in cells | `80x24`, `120x40`, `200x60`, `40x12` |
| `n` | The data count, synthesised from the case's seed by `Synth` | an integer |
| `script` | Phases separated by `;`. A phase is a step, with an optional `*k` to repeat it | see below |
| `scales` | The complexity class the counts must keep, checked by running again at a larger n | `flat` (equal at 10n), `linear` (twice at 2n, ±10%), `-` |
| `timed` | Whether the timed sweep includes it | `t` or `-` |
| `tags` | What it exercises, comma-separated, for `--tags` | free words, from a listed set |

Script steps are named after `TestApp`'s methods, so a test author already knows them. Each phase
is counted separately, because a first frame and a keystroke are different frames:

| Step | Meaning |
|---|---|
| `open` | The first frame. Always the first phase, implied if omitted |
| `idle` | A frame with nothing changed |
| `wheel:+k` / `wheel:-k` | `scroll(.down/.up, by: k)` over the composition's middle |
| `key:<name>` | `press(_:)`: `pgdn`, `pgup`, `end`, `home`, `down`, `right`, `tab`, `bksp` |
| `type:<text>` | `type(_:)`, a character per frame |
| `hover:+k` | The pointer moved k rows down |
| `resize:<w>x<h>` | `resize(width:height:)` |
| `tick:<ms>` | `advance(by:)` |
| `append:k`, `edit:mid`, `remove:0`, `move:a>b`, `replace` | Writes to the composition's model (`CaseRows`, an `@Observable` of synthesised rows), outside any render |

Every case is played with its colour depth, locale and appearance pinned. Bytes written depend on
all three, and `swift test` sets `NO_COLOR` when its output is piped, so without the pins a byte
count would depend on how the gate was invoked.

### Ten cases, written in it

```
id                  composition                    in      size     n      script                               scales  timed  tags
list-wheel          list.plain                     alone   80x24    10000  open;wheel:+5*20                     flat    t      list,window
list-hover          list.plain                     alone   80x24    10000  open;hover:+1*20                     flat    -      list,hover,bytes
list-search         list.search                    alone   80x24    10000  open;type:ab;key:bksp*2              linear  -      list,search,invalidate
table-fit-tail      table.fit5                     alone   120x40   2000   open;append:1*50                     flat    t      table,memo,tail
tabs-switch         tabs(list.plain,table.fit5)    alone   120x40   3000   open;key:tab;key:right*10            flat    -      tabs,offscreen
chat-lazy-follow    chat.lazy                      bottom  80x24    5000   open;append:1*100                    flat    -      scroll,anchor,lazy
chat-eager-follow   chat.eager                     bottom  80x24    500    open;append:1*20                     linear  t      scroll,anchor,eager
editor-typing       editor.wrap                    alone   100x30   2000   open;key:pgdn*10;type:hello;idle*5   flat    t      editor,wrap,invalidate
split-resize        split(list.plain,table.fit5)   alone   200x60   3000   open;resize:80x24;resize:200x60*5    flat    -      split,resize,narrow
mail-idle           stress:app-shapes/mail-client  -       120x40   1      open;idle*200                        -       t      appshape
```

What each one asks:

1. `list-wheel`: the windowed list's steady scroll. The rows built per wheel step must not depend
   on n. This is `PulledListTests.builtRowsIndependentOfRowCount`, as a row.
2. `list-hover`: the owner's 2026-11-10 ruling that hover moves the list row. A hover step should
   rebuild two rows and write two rows' bytes. Nothing measures this today.
3. `list-search`: `.searchable` filtering over 10,000 rows. The app's filter is O(n), so
   `linear`. The bodies count says whether rows that are filtered out still run.
4. `table-fit-tail`: a `.fit` column with a row appended per frame. The `.fit` memo must look at the
   new row, not rescan all 2,000 (the O(rows) scan found by `sweep.py`, kept from coming back).
5. `tabs-switch`: whether a hidden tab's table is built, measured or drawn, and what a tab switch
   costs on each side.
6. `chat-lazy-follow`: bottom-anchored, variable-height rows with one appended a frame. The
   `scrollfollow` claim (O(window) at any n), now with a count that fails if it breaks.
7. `chat-eager-follow`: the eager half of the `chat` pair, timed because the pair is the
   measurement, and `linear` because an eager stack is meant to be.
8. `editor-typing`: a wrapped `TextEditor` paged to its middle and typed into. The lines re-wrapped
   per keystroke must not depend on the document's length.
9. `split-resize`: a split view of a list and a table, resized narrow and back. The rows rebuilt
   per resize, and whether `.fit` widths are recomputed once or once per pass.
10. `mail-idle`: an existing `app-shapes` variant adopted as a row with no new code, so the table can
    take over the timed sweep's scenarios one by one.

### The recorded counts

`Stress --check-counts` plays every case and writes or compares
`Sources/Stress/Cases/RecordedCounts.txt`, one line per case and phase, holding the per-frame mean
over the phase's frames:

```
case                phase             frames  built  served  bodies  cells  misses  bytes
list-wheel          open              1       ?      ?       ?       ?      ?       ?
list-wheel          wheel:+5          20      ?      ?       ?       ?      ?       ?
list-wheel@10n      wheel:+5          20      ?      ?       ?       ?      ?       ?
```

The `?`s are deliberate: none of these numbers has been measured, and lane 2 records the first
ones. The `@10n` line is the `flat` check's second run. The checker compares its counts with the
`n` line's, not with a recorded value.

Rules:

- `built`, `bodies`, `cells` and `bytes` must match exactly. Any difference fails, in either
  direction. A count that falls is good news, and the table records it so it cannot quietly come
  back, as `check-ratchets.py` does for its limits.
- `served` and `misses` may move by 1% before failing. The value memo keys some values by an
  address, and its hits vary by a few in a thousand between runs of one build.
- `TUI_RECORD_PERF_COUNTS=1` re-records, following the `TUI_RECORD_SNAPSHOTS` convention. The
  commit that re-records says, per case, what moved and why, as the profiling rule in `CLAUDE.md`
  already asks of a commit motivated by profiling.
- A failure prints the case, the phase, the old and new line, the re-record command, and the
  `Stress --session case:<id>` line that reproduces it.

### Fitting it into the gate

| Where | What runs | Cost |
|---|---|---|
| Gate (`gates_inline.sh`) and CI, beside `--selfcheck` | `Stress --check-counts`, debug, every case | A budget, not a measurement: 60 s serial for 300 cases. If it grows past that, `--shard i/n`, or option 2(b) |
| `--selfcheck` | Every case once, memo-verified, plus its `check` if the composition has one | Grows with the table, as it does with every variant now |
| On demand, quiet machine | `ab_bench.py --cases timed`, or `--tags table,memo` | About 90 s per case; the `timed` set kept to about an hour |
| On demand, any machine | `ab_counters.py` (release, adds allocations), `frame_parity.py` | Minutes; unchanged tools |

Linux matters. CI runs `--selfcheck` on its Linux lanes, so it would run `--check-counts` there
too. Whether every count is the same on Linux and macOS is not known. Foundation's formatting and
grapheme widths are candidates for a difference. Lane 2 runs the table on both before the check
gates anything, and a case whose counts differ by platform carries a `@linux` line of its own
rather than a tolerance.

### What stays as it is

The named scenarios and sessions stay. They are the right unit for a shape worth a name, and many
carry `check`s that a generic case cannot. `ScrollFitBaselineTests` stays where it is while the
SCROLL-FIT lanes are editing it. Its subjects and situations are the seed of `CaseComposition` and
`CaseContainer`, and folding them together waits until SCROLL-FIT has landed. The hand-rolled
counting tests stay too: each one guards a particular fix, with an assertion written for it.

## The lanes

One landing stream, in order. Lane 4 can split by family once lane 2 has landed, because the
table is one file per family (`Cases/Lists.swift`, `Cases/Tables.swift`, …), so parallel lanes do
not touch the same lines.

| Lane | What | Days |
|---|---|---|
| L1 | A bodies-run counter on `RenderCache`, beside `RowWork`, priced with `ab_bench.py --quick` (one increment on a class, not a `RenderContext` field). `Stress/Cases/`: the vocabulary enums, `CaseRows`, and a table parser that reports line numbers | 1.5 |
| L2 | `--check-counts` with the recorded file, tolerances, re-record, and the `flat`/`linear` reruns. The ten cases above. A planted regression for each count (the pull switched off, the `.fit` memo bypassed), confirming the check fails without the fix. Run on macOS and Linux; settle the platform question. Add to `gates_inline.sh` and CI | 2 to 2.5 |
| L3 | A generic `CaseSession` and the `cases` matrix scenario, so cases appear in `--sessions` and `--variants`. `--cases [--timed] [--tags]` listing. `ab_bench.py` and `sweep.py` take `--cases`/`--tags`. Check `frame_parity.py` and `ab_counters.py` read cases unchanged | 1.5 |
| L4 | Populate about 100 cases over the situations not yet profiled: sheets, popovers, tab views, split views, narrow and tiny terminals, outline lists, grids, forms, focus traversal, hover, resize storms. Each surprising count is filed as a finding, not fixed in the lane | 2 to 3 |
| L5 | Documentation: a "Cases" section in the `Stress` README, the Profiling README's A/B section, `CONTRIBUTING.md`'s note on performance tests. The timing-trend script, if A-PERFCASE-3 says yes | 1 |

About 8 to 9.5 lane-days in all, roughly two weeks of one stream.

## Questions for the owner

### A-PERFCASE-1. Exact counts, or bounds?

**Owner, 2026-11-14: exact, and improvements are, of course, not failures.** Exact counts catch
flakiness and quantify improvements as well as regressions. So a rise fails, a fall passes and is
reported until re-recorded, and a case counted twice must agree (B-PERFCASE-4).

Recommended: exact recorded counts for `built`, `bodies`, `cells` and `bytes`, failing in both
directions, with 1% on the memo counts. The alternative is upper bounds (`built < 100`), which
never need re-recording but let a count drift up to its bound unseen, and say nothing when a
change improves one. The cost of exact counts is a re-record in every commit that changes what a
case does. Pricing that: a change to `List`'s windowing could re-record a few dozen lines, all in
one generated file.

### A-PERFCASE-2. Does the check run in `Stress` or in a test target?

**Owner, 2026-11-14: in `Stress` (as recommended).**

Recommended: in `Stress`, as `--check-counts` (B-PERFCASE-3). It needs no new target and no
compile-time cost outside `Stress`. A test target gives per-case reporting and parallel runs, in
exchange for a library target shared with `Stress`.

### A-PERFCASE-3. Keep a timing trend?

**Owner, 2026-11-14: yes (as recommended).**

Recommended: yes, as a CSV in the working notes, appended by any `ab_bench.py --cases timed` run
on the owner's machine. It costs nothing to the repository, and it shows drift that no single A/B
was set up to catch. The alternative is no timing trend: counts only, and A/Bs when a change is
suspected.

## Where it stands

Proposed 2026-11-14; the owner answered A-PERFCASE-1 to 3 the same day. B-PERFCASE-1 to 7 are decided here and
stand unless the owner's answers change them. Lanes 1 and 2 were built on 2026-11-15 ("Lanes 1 and 2, as built",
below), lane 3 on 2026-11-16 ("Lane 3, as built"), lane 5 the same day ("Lane 5, as built"); lane 4's first forty
cases on 2026-11-17 ("Lane 4, the first part"), and about sixty are still to come.

## Lanes 1 and 2, as built (2026-11-15)

**The counter.** `RenderCache.RowWork.bodies` counts every composite body the walks evaluate, incremented in
`BodyChangeReport.noteBodyEvaluated`, the one call every evaluated body is followed by (B-PERFCASE-6).
`RenderCache.rowWork` became `@exclusivity(unchecked)`, since it is now written once per body. Its price:
`ab_bench.py --quick`, release, against its base (d642eb2a1), load 3.2 to 5.5: indistinguishable in all seven
scenarios, medians −0.3% to +2.1%, the tightest intervals `modifiers` −1.7%…+0.8%, `framedcolumns` −0.4%…+1.3% and
`table-churn` −0.8%…+0.3%. No measurable cost.

**The cases.** `Sources/Stress/Cases/`: the vocabulary (`CaseVocabulary.swift`), the rows every composition reads
(`CaseRows.swift`), the parser (`CaseTable.swift`, `CaseTable+Script.swift`), the pages (`CaseCompositionView.swift`),
the player (`CasePlayer.swift`, a `HeadlessApp` per play), the check (`CountCheck*.swift`), the known issues
(`CaseKnownIssues.swift`) and the ten cases, one file per family under `Tables/`. `Stress --check-counts` plays them
in about 35 s, debug, on the development machine.

Where the build differs from the design above, and why:

| Design | As built | Why |
|---|---|---|
| The recorded file holds per-frame means | It holds the phase's totals, with its `steps` and `frames` | A total compares exactly; a mean of 3 frames does not. `frames` is a count too: a page that starts asking for frames it does not need fails on it |
| `@10n` lines are compared with the `n` lines only | They are recorded and compared exactly as well, besides the scaling check | They cost nothing, and a finding that gets worse at 10n then fails even where its scaling is excused |
| `linear` is "twice at 2n, ±10%" | Each count at 2n is the count at n or twice it, ±10% | A case's chrome and its first frame's fixed work do not double; what `linear` rules out is worse than O(n) |
| Scaling compares every count | It compares `built`, `served`, `bodies`, `cells` and `misses`, not `bytes` | A scroll bar's thumb sits elsewhere at 10n: `list-wheel` writes 33,981 bytes at n and 33,558 at 10n for the same rows |
| `list-search` is `linear` | `flat` | The O(n) filter is the app's own code, which no count sees; the framework's work is O(window) at any n, so filtered-out rows run no body |
| `list-search` is `open;type:ab;key:bksp*2` | `open;key:tab;type:ab;key:bksp*2` | The list holds the focus as the page opens, as on macOS; the Tab reaches the search field |
| `tabs-switch` is `open;key:tab;key:right*10` | `open;key:right;key:left;key:right;key:left` | The tab strip holds the focus as the page opens: the Tab moved it into the list, and no Right switched a tab (0 bytes) |
| A failure names `Stress --session case:<id>` to reproduce | `Stress --check-counts --case <id> [--show]`, `--show` printing the last frame | The generic `CaseSession` is lane 3's |
| Rows synthesised by `Synth` from the seed | Content repeats every 100 ids (`CaseRows.period`) | The rows at the end of a list of 10n are then the rows at the end of a list of n: a bottom-anchored rerun draws the same rows at the same heights |
| A case with a broken scaling class fails | A finding can excuse named counts of one case (`CaseKnownIssues`), printed as `KNOWN` on every run | Findings are filed, not fixed in the lane; a case keeps the class it is for |

What each failure prints: the case, the phase, the recorded and the new line, the command that plays the case
again and the one that re-records it, and on Linux the `@linux` line ready to paste. `--check-counts` also unsets
every `TUI_` variable and `NO_COLOR`, `COLUMNS` and `LINES`, and pins the language and locale to English (US)
before anything reads them; the colour depth is pinned per frame, at 24 bits, as `TestApp` pins it.

**Determinism.** Every case agreed with itself across two plays in one process and across processes (whose
`Hasher` seeds differ), in every count, `served` and `misses` included: the 1% they may move has not been needed.

**The recorded counts** (totals over each phase; `@10n` and `@2n` lines left out):

| Case | Phase | Steps | Frames | Built | Served | Bodies | Cells | Misses | Bytes |
|---|---|--:|--:|--:|--:|--:|--:|--:|--:|
| `list-wheel` | `open` | 1 | 2 | 94 | 0 | 196 | 0 | 176 | 5,595 |
| `list-wheel` | `wheel:+5` | 20 | 20 | 306 | 140 | 700 | 0 | 600 | 33,981 |
| `list-hover` | `open` | 1 | 2 | 94 | 0 | 196 | 0 | 176 | 5,595 |
| `list-hover` | `hover:+1` | 20 | 20 | 6 | 440 | 100 | 0 | 0 | 0 (5,132 since F4 was withdrawn) |
| `list-search` | `open` | 1 | 2 | 90 | 0 | 232 | 0 | 312 | 5,558 |
| `list-search` | `key:tab` | 1 | 1 | 21 | 0 | 58 | 0 | 78 | 1,172 |
| `list-search` | `type:ab` | 1 | 2 | 45 | 0 | 122 | 0 | 184 | 3,020 |
| `list-search` | `key:bksp` | 2 | 2 | 42 | 0 | 119 | 0 | 170 | 2,947 |
| `table-fit-tail` | `open` | 1 | 2 | 120 | 36 | 28 | 30,740 | 8 | 10,441 |
| `table-fit-tail` | `append:1` | 50 | 50 | 62 | 1,800 | 350 | 515,625 | 100 | 0 |
| `chat-lazy-follow` | `open` | 1 | 3 | 81 | 31 | 409 | 0 | 1,305 | 3,724 |
| `chat-lazy-follow` | `append:1` | 100 | 100 | 120 | 1,381 | 3,004 | 0 | 13,816 | 42,370 |
| `chat-eager-follow` | `open` | 1 | 3 | 2,010 | 1 | 7,040 | 0 | 20,060 | 3,724 |
| `chat-eager-follow` | `append:1` | 20 | 20 | 10,225 | 0 | 21,680 | 0 | 64,780 | 8,076 |
| `tabs-switch` | `open` | 1 | 3 | 121 | 1 | 262 | 15,000 | 279 | 10,481 |
| `tabs-switch` | `key:right` | 1 | 2 | 44 | 36 | 30 | 30,360 | 46 | 7,643 |
| `tabs-switch` | `key:left` | 1 | 1 | 41 | 0 | 84 | 0 | 86 | 7,131 |
| `tabs-switch` | `key:right#2` | 1 | 1 | 3 | 36 | 15 | 15,180 | 23 | 7,643 |
| `tabs-switch` | `key:left#2` | 1 | 1 | 39 | 0 | 84 | 0 | 86 | 7,131 |
| `split-resize` | `open` | 1 | 3 | 366 | 173 | 532 | 61,140 | 505 | 24,566 |
| `split-resize` | `resize:80x24` | 1 | 1 | 105 | 0 | 175 | 12,044 | 239 | 6,723 |
| `split-resize` | `resize:200x60` | 5 | 5 | 130 | 236 | 157 | 15,285 | 118 | 122,830 |
| `editor-typing` | `open` | 1 | 2 | 6 | 0 | 20 | 0 | 8 | 5,377 |
| `editor-typing` | `key:pgdn` | 10 | 10 | 3 | 0 | 50 | 0 | 20 | 26,020 |
| `editor-typing` | `type:hello` | 1 | 5 | 3 | 0 | 25 | 0 | 10 | 852 |
| `editor-typing` | `idle` | 5 | 5 | 0 | 0 | 25 | 0 | 10 | 0 |
| `mail-idle` | `open` | 1 | 3 | 107 | 35 | 8,176 | 0 | 42,520 | 11,573 |
| `mail-idle` | `idle` | 200 | 200 | 6 | 7,000 | 4,200 | 0 | 12,800 | 0 |

**Findings** (filed, not fixed here):

- **PERFCASE-F1.** A row appended to a `Table` rescans every row of every `.fit` column: `table-fit-tail` reads
  515,625 cell values over 50 appends at 2,000 rows (5 columns × 2,062 rows a frame), 5,015,625 at 20,000. The
  fit-width memo is keyed by the rows' data, which an append changes, so the O(rows) scan `sweep.py` found is still
  there for a growing table. `split-resize` pays it on every resize. **Fixed (2026-11-16):** each `.fit` column keeps
  its walk in `@State` as well (`_TableFitRecord`, `TableFitRecord.swift`), which the write that brings a row does not
  sweep, and extends it by the rows a collection grew by — the lazy stack's content-width record
  (`StackContentWidth.swift`) followed rung for rung, challenge included. `table-fit-tail`'s 50 appends now read 9,750
  cell values at n and at 10n alike: the drawn rows, the new row and, after the write, the row that decided each
  width.
- **PERFCASE-F2.** A hidden tab's `.fit` table scans its columns at open: `tabs-switch` reads 15,000 cell values
  (5 × 3,000) for a table nothing draws. And every switch to it read them again, the cache's entry pruned by the
  frames the tab was hidden in. **Fixed (2026-11-16)** with PERFCASE-F1: the record is in the table's `@State`, which
  a tab view keeps for its hidden tabs, and the second switch reads 362 cell values (15,180 before), at n and 10n.
  The read at open stays — the tab view measures every tab once for its panel's size, and a `.fit` width is a walk of
  every row — and so does the first switch's, for PERFCASE-F5.
- **PERFCASE-F5.** A whole-cache clear (`RenderCache.clearGeneration`) makes a `.fit` column's kept walk stale, as it
  makes a lazy stack's content width stale, and every row is read again: twice as `table-fit-tail` opens (30,740 at
  n), at the first switch to `tabs-switch`'s table (30,360), and at each of `split-resize`'s resizes, since a new
  terminal size moves the `EnvironmentSnapshot`. Not every such clear moves anything a cell's width depends on — a
  resize moves only the terminal's size — but the counter does not say which; a record that could tell them apart
  would serve all three.
- **PERFCASE-F3.** The bottom-anchored lazy stack is not O(window): at 10n `chat-lazy-follow` runs 21% more bodies
  and misses 29% more measures as it opens, and 10% and 19% more per row appended.
- **PERFCASE-F4, withdrawn: the case's mistake, not the code's.** It said a hover moves nothing on a `List`, since
  `list-hover` wrote no byte over 20 steps, and that the owner's ruling was not built. It was false. The ruling
  (HOVER-FOCUS b, built in 217c8bdf5) is for a scene whose focus follows the pointer: hovering a row then moves the
  list's cursor row and the focus, never the selection. The case played a `List` without `.focusFollowsPointer()`,
  and `--check-counts` unsets every `TUI_` variable, `TUI_FOCUS_FOLLOWS_POINTER` with it, so a hover rightly moved
  nothing. The composition is now `follows(list.plain)` (`follows(…)`: the page in a scene with
  `.focusFollowsPointer(true)`, drawn with no extra view, so only what the setting does moves a count), and the
  case re-recorded (2026-11-16): a hover step now writes 257 bytes (5,132 over 20 steps), two rows' worth, and
  rebuilds no row. The cursor's highlight is drawn over rows the memo serves (22 a step, as before), so the
  design's "two rows rebuilt a step" was itself wrong; every other count is unchanged.
- `tabs-switch`: switching back to the list tab rebuilds its visible rows (41 built, none served) every time, and
  the design's script, `key:tab;key:right*10`, switched nothing: the tab strip holds the focus as the page opens,
  so the Tab moved the focus into the list, where Right does nothing (0 bytes). The case now plays
  `key:right;key:left;key:right;key:left`.
- `mail-idle`: an idle frame of the mail client, nothing changed, runs 21 bodies and misses 64 measures.

**Planted regressions.** Each count's check was seen to fail with the regression planted, and pass without it:

| Count | Planted | Seen failing |
|---|---|---|
| (the table) | `list.plane` and `wheel:5` in `Lists.swift` | Both reported, each at its own line of the file (18, 19) |
| `bytes` | The diff writer forgets the last frame (`previousLines: []`) | 46 lines in all 10 cases |
| `misses` | The measure memo never answers | `misses` on 16 lines (`list-search`, `tabs-switch`, `mail-idle`), `bodies` with it |
| `cells` | A `Table`'s `.fit` width memo bypassed: the doc's planted regression | `cells` on 6 lines (`table-fit-tail`, `split-resize`) |
| `built`, `bodies` | The value memo never serves a row | `built` and `bodies` on 20 lines each, in 7 cases; `served` fell (printed as improved) |
| `served` | The row window takes 20 rows past the viewport: the pull switched off, as the doc says | `served` on 10 lines, `built` on 24 |
| `frames` | Every render asks for another frame, as a page that never idles does | `frames` on 54 lines in all 10 cases |

Each was planted in the source, built, checked, and taken out again; the tree without it passes.

**In the gate and CI.** The gate (`gates_inline.sh`, in the working notes) runs `Stress --check-counts` after
`--selfcheck`, in its build-dependent phase, and passes only with its `check-counts: all` line; a tree from before
the cases says `check-counts: absent` instead. CI runs it after the selfcheck step in the macOS and the Linux jobs
(not Windows, where `TUIApp`, and so `HeadlessApp`, does not build).

**Left for lanes 3 to 5.** The generic `CaseSession` and the `cases` matrix scenario, so cases are in `--sessions`,
`--variants` and `--selfcheck` (memo-verified); a `--cases [--timed] [--tags]` listing; `ab_bench.py` and
`sweep.py` taking `--cases`/`--tags` (L3, built 2026-11-16: "Lane 3, as built", below). About a hundred more cases, each surprising count filed as a finding
(L4). The `Stress` README's section and the Profiling README's, `CONTRIBUTING.md`, and the timing-trend CSV the owner
said yes to (L5). The three findings above that stand (F1 to F3) are for whoever takes them.

**The platform question.** Settled by reasoning and a build, not yet by a Linux run (nothing here runs Linux): CI runs
`--check-counts` on the Linux lanes as on macOS, binding, against the same recorded lines. What a count depends on is
the same on both. The cases draw ASCII text whose widths come from TUI's own tables, not the C library's; no case
draws an SF Symbol (whose glyph depends on the host's fonts, which is why `750e1de04` took one out of the SCROLL-FIT
baseline); none sorts (`TableColumn`'s comparator is the one Darwin-only branch on a case's path); the numbers drawn
are interpolated, not formatted; the language, locale, colour depth and `TUI_` variables are pinned; and `Hasher`'s
per-process seed, which differs on every run on both platforms alike, has moved no count (see Determinism). A
static-linux build (swift.org 6.3.3, musl) of `Stress` with the cases builds with no error or warning of the code's (2026-11-15). If a Linux lane does find a phase
that differs, its failure prints the `@linux` line to add, and that platform then reads it in place of the shared
one.

## Lane 3, as built (2026-11-16)

Every case is now where the harness's other tools look (B-PERFCASE-3), with no tool learning a new kind of thing:

- **`CaseSession`** (`Cases/CaseSession.swift`): a case's script as a `Stress` session, `case:<id>`, after every
  other session in `--sessions`. It plays in the app `--check-counts` plays in (`PerfCase.app(page:)`, through a new
  `StressSession.makeApp(width:height:)`, `nil` for every other session), at 24-bit colour, and at the case's size
  whatever `--cols`/`--rows` say (`SessionDescriptor.size`, applied by `SessionRunner.Options.sized(for:)` wherever a
  session is run and reported). `--scale` multiplies its `n`.
- **The `cases` matrix scenario** (`Cases/CaseMatrix.swift`): every case's page at rest, a variant each, grouped in
  `--variants` by the table it is written in. An adopted case has no variant, its page being a scenario's already.
  One translated title, no string per case (B-PERFCASE-5). `ab_bench.py` leaves it out of its default sweep, as it
  leaves `animating` and `translucent`: a case is timed through `--cases`.
- **`Stress --cases [--timed] [--tags a,b]`**: a line per case in the table's columns, its id first and no header,
  machine-read as `--variants` is. `--tags` keeps the cases with any of the tags; a tag `CaseTags` does not know, or a
  table with mistakes, exits 1.
- **`ab_bench.py` and `sweep.py`** take `--cases` (every case, `timed`, or ids) and `--tags`, and time or survey each
  case as `session/case:<id>`. `ab_bench.py` skips a case the base binary lacks, as it skips a scenario.
- **`frame_parity.py` and `ab_counters.py` read cases unchanged**: both take every session `--sessions` lists, and
  `frame_parity.py` every variant, so with no `--scenarios` they play the case sessions and (`frame_parity.py`) the
  `cases` pages too; `session/case:<id>` names one.

Where the build differs from the design, and why:

| Design | As built | Why |
|---|---|---|
| A case with a script plays as a session; one without, as a variant | Every case is both: a session plays its script, a variant draws its page at rest | Every case has a script (`open` at least), and a page at rest is what `sweep.py` and `frame_parity.py` survey across variants |
| The session plays the script | The script loops after its `open`; a step is one frame; `type:ab` is a step per character; `tick:<ms>` is an idle step | A session plays as many steps as asked (a bench's iterations); the runner draws one frame a step and owns the clock |
| `--sessions`'s ids as they are | `--selfcheck` pads a session's id without cutting it | `session/case:chat-eager-follow` is longer than the 26 columns the ids were cut to |

What the selfcheck costs: the ten case sessions, each played 150 steps against its cache-cleared twin with the
terminal resized every 37, add about two minutes, debug, to the gate's eighteen: `list-search` 46 s (its O(n) filter
over 10,000 titles runs per keystroke in both instances), `mail-idle` 29 s, `chat-eager-follow` 17 s, the other
seven 1 to 9 s each. The nine pages at rest add seconds. All pass.

The misses this lane saw rise as `chat-lazy-follow` and `tabs-switch` open (1305 → 1322 and 279 → 283, 1 to 2%
throughout) are its own harness's, not `main`'s: `--check-counts` on `main` at 4accf58ea matched exactly, twice, and
this lane's commits change no TUI source. The likely cause is that every case's scene now carries
`.focusFollowsPointer(_:)` for `list-hover`. They were re-recorded with the `.fit` record (cce0fed95).

## The `listed` count (2026-11-16)

**Why.** The first outline cases (finding G1, from building tuitree: a `List(_:children:)` describes every open row
on every pass) played 5,000 open rows in 5.9 s where a flat list of 10,000 plays in 0.4 s, and every count stayed
flat at 10n. What the outline paid for was a row *box* per open row a pass, its closures, its identity and its ids,
none of which draws anything, runs a body or misses a measure, so no column saw it. A box is the unit a windowed
`List` saves: it makes one for the rows it walks and none for the rest.

**What.** `RenderCache.RowWork.listed` counts the row boxes a `List` makes (`LazyListRowContent`), drawn or not:
counted where a `ForEach` row's box is made (`makeListRowContent`), where a child walk's row's is
(`deferredListRow`, `loneListRow`), and where an outline's is. The table gained a `listed` column after `frames`,
and `listed` joined the counts a scaling rerun is held to. Recording it moved no other count of the ten cases, and
it is 0 for every case with no `List` in it.

| Case | Phase | Listed |
|---|---|--:|
| `list-wheel` | `open` | 88 |
| `list-wheel` | `wheel:+5` (20 steps) | 440 |
| `tabs-switch` | `open` | 111 |
| `split-resize` | `open` | 290 |
| `mail-idle` | `open` | 6,104 |
| `mail-idle` | `idle` (200 steps) | 5,200 |

`mail-idle` makes 26 boxes an idle frame for the boxes its lists show: a box is made again every pass, cheaply,
and served from the row memo when it is read, which is why `built` there is 6 over 200 frames.

A `Table`'s rows count too where its tree is row content (`Table(of:columns:rows:)` with a `DisclosureTableRow` or
an `OutlineGroup` of table rows, as tuitree's is): such a tree exists only as the app's row builders, so a pass
flattens it again, building every open row's content, and `listed` counts the rows that flattening lists, drawn or
not (`_TableCore.resolveRows`). A `Table(_:children:)` keeps its outline from pass to pass and builds no row content
to make it, so it lists none: `outline-table` is 0 throughout. Counting it moved no count of any recorded case.

**`Table(_:children:)` counted too (2026-11-16).** It lists no row content, but it makes its kept outline again
whenever its open branches change, and that work was invisible: tuitree's → and ← on 200,000 open rows cost 240 ms
where ↓ cost 8 (finding M6-2), and every count of `outline-table` stayed flat. Now `listed` counts the rows each
outline it makes lists (`_TableOutlineCache.listed`, added to the pass's `RowWork.listed`); a pass that changes
neither its roots nor its open branches makes none and lists none. Re-recorded, on a clean debug build:

| Case | Phase | Listed at n | Listed at 10n |
|---|---|--:|--:|
| `outline-table`, `outline-children-bound` | `open` | 0 → 1 | 0 → 1 |
| | `key:oright` | 0 → 5,001 | 0 → 50,001 |
| | `key:left` (2 steps) | 0 → 4,992 | 0 → 49,992 |
| | `key:right` | 0 → 5,001 | 0 → 50,001 |

`key:oright` opens every row from the root, so listing them is its change, at any build. `key:left` and `key:right`
close and reopen one group of nine rows, and list every open row: M6-2, filed as both cases' known issue. No other
count of any case moved.

**`outline-toggle` (2026-11-16).** M6-2's own shape: one branch opened and closed in a big open outline. Its page,
`outline.open`, is `outline-children-bound`'s table with every branch open from the start, the app's set holding
them all, as tuitree's tree is after an ⌥→ on its root: at n = 50,000, 50,001 rows and 5,001 open branches. The
script goes down to the first group (a branch of 99 rows, nine of them branches of nine), closes it with Left, opens
it with Right, closes it and its nine with ⌥Left, opens them all with ⌥Right, and goes back up, so the session loops.
Recorded on a clean debug build, every toggle lists every open row:

| Phase | Listed at n | Listed at 10n |
|---|--:|--:|
| `open` | 50,001 | 500,001 |
| `key:left`, `key:oleft` | 49,902 | 499,902 |
| `key:right`, `key:oright` | 50,001 | 500,001 |
| `key:down`, `key:up` | 0 | 0 |

The first frame lists the open tree, which is what opening it costs; the toggles are M6-2, the case's known issue.

**Spliced (2026-11-16).** M6-2 fixed: given the same roots and a changed set, the kept outline is spliced rather than
made again (`_TableOutline.splicing(_:to:expansion:)`, `TableOutlineSplice.swift`). The ids that changed come from the
outline's own writes where they lead from the reading the cache last saw to the one it sees now, else from comparing
the two sets; only the shown branches whose triangle no longer matches are turned, in reading order, each outermost one
once, its rows flattened as a tree of one root and put in, or taken out. Every other row is copied, values and places
in bulk and each parent link moved by the runs before it, in a merge that is not generic over the rows' values (the
row types are top-level since a74bc4ec2: nested in the generic outline, a third of a toggle went in metadata lookups). The
index by id moves to the new outline with the splices noted, a lookup replaying those since its row was noted. Shared
ids, rows with traits or loops, or a new store fall back to the whole flattening. The paragraph under "(d) chosen and
built" that set splicing aside is answered by both: the links that shift are moved by runs, and branch nodes stay put.

Re-recorded on a clean debug build, `listed` now counts the rows a change puts in or takes out:

| Case | Phase | Listed at n, before → after | At 10n, before → after |
|---|---|--:|--:|
| `outline-toggle` | each of `key:left`, `key:right`, `key:oleft`, `key:oright` | 49,902 or 50,001 → 99 | 499,902 or 500,001 → 99 |
| `outline-table`, `outline-children-bound` | `key:left` (2 steps) | 4,992 → 9 | 49,992 → 9 |
| | `key:right` | 5,001 → 9 | 50,001 → 9 |
| | `key:oright` | 5,001 → 5,000 | 50,001 → 50,000 |

Flat, so the known issues keep only what is the change itself: ⌥→ on the root (it now lists the rows it puts in, not
the root again) and `outline-toggle`'s first frame. No other count moved. Timed (`ab_bench.py --exclusive`, release,
cpu-per-frame, against the case's commit): `outline-toggle` 29,581 → 1,510 µs (−94.9%), `outline-children-bound`
−42.1%, `outline-table` −37.0%; the other outline cases and the eight table scenarios indistinguishable but for
`tables-vstack` (−4.4%). What a change still costs beyond its rows is one copy of the kept rows (no node built, no id
hashed), and without a write of the outline's own, one comparison of the two sets.

## The outline cases (2026-11-16)

Finding G1, from building tuitree, had two shapes left after `List(_:children:)` was windowed (a5b20c46f): a
`Table(of:columns:rows:)` whose rows are a tree written as row content, which is the table tuitree draws, and an
outline inside a `Section` of a `List`. Two cases play them over the same tree and script as `outline-list` and
`outline-table` (`Tables/Outlines.swift`), `flat` at 5,000 and 50,000 open rows:

| Case | Composition | What it draws |
|---|---|---|
| `outline-rows` | `outline.rows` | `Table(of:columns:rows:)`, its rows `CaseNodeRows`: a `ForEach` of a `DisclosureTableRow` for each branch, its rows the same content again over its children, and a `TableRow` for each leaf, as tuitree's `NodeRows` |
| `outline-section` | `outline.section` | `List { Section { OutlineGroup(_:children:) } }` |

Recorded on a clean debug build:

| Case | Phase | Steps | Listed at n | Listed at 10n |
|---|---|--:|--:|--:|
| `outline-rows` | `key:oright` | 1 | 5,001 | 50,001 |
| `outline-rows` | `wheel:+5` | 10 | 50,010 | 500,010 |
| `outline-rows` | `key:pgdn` | 3 | 15,003 | 150,003 |
| `outline-rows` | `key:left` | 2 | 9,993 | 99,993 |
| `outline-rows` | `key:right` | 1 | 5,001 | 50,001 |
| `outline-section` | every phase but `open` | | 1 a step | 1 a step |

**Findings:**

- **G1-rows.** The table's outline is flattened again every pass, each open row's content built by the app's row
  builders: n + 1 rows a frame, every other count the same as `outline-table`'s. Filed as the case's known issue.
  The case plays in 2.6 s where `outline-table` plays in 0.6 s.
- **G1-section.** `outline-section` is flat only because nothing opens: Option-Right, Left and Right do not reach an
  outline inside a `Section`. The list asks the view its rows came from to open a row (`RowSource.rowsContent`),
  and for a section that is the `Section`, which opens nothing. The rows are still extracted all at once.
  **Keys fixed (2026-11-16):** each section hands its outline up (`SectionContentRows.rowsContent`), the list keeps
  every section's (`RowSource.sectionOutlines`, one `SectionOutlines` for several), and the keys open and close it as
  in `List(_:children:)`. Re-recorded, the case now opens its tree and shows what remains: a box for every open row
  on every pass, the counts `outline-list` had before it was windowed (`wheel:+5` 50,010 at n, 500,010 at 10n), filed
  as its known issue. **Windowed (2026-11-16):** a section whose content is an outline hands its rows over
  windowed (`SectionContentRows.windowed`), and a list whose content is that one section draws them as a list of the
  outline alone does, the header before them and the footer after (`_ListCore.windowedSectionSource`). `listed` falls
  to `outline-list`'s, at n and 10n alike (`wheel:+5` 50,010 to 220), and the known issue is gone. A section among
  other rows, or several sections, still extracts its rows at once.

**`outline-rows-stacked` (2026-11-16).** tuitree's table is not the whole page: it sits in a stack under other
views, and a stack measures its children before it draws them. Timed in tuitree (release, a 3.2 MB file, about
200,000 rows open), a key cost 2.3 to 3 s, and a Time Profiler attach put 92.7% of it in the table's preparation,
reached once from the measure (68.4% of samples) and once from the draw (24.3%): each flattened the tree again. A
container was added for that shape, `stacked` (`VStack { title; it }`, filling the page), and a case of the table
in it, recorded on a clean debug build. It lists every open row twice a frame, where `outline-rows` lists them once:

| Case | Phase | Steps | Listed at n | Listed at 10n |
|---|---|--:|--:|--:|
| `outline-rows-stacked` | `key:oright` | 1 | 10,002 | 100,002 |
| `outline-rows-stacked` | `wheel:+5` | 10 | 100,020 | 1,000,020 |
| `outline-rows-stacked` | `key:pgdn` | 3 | 30,006 | 300,006 |

Filed under G1-rows with `outline-rows`; the second listing a pass is not part of the row-builder contract
question, and is the case's to remove.

**Once a pass (2026-11-16).** The table flattens its tree once a pass at its place and hands that outline to every
measure and the draw (`RenderCache.composedOncePerPass(for:context:readsLayout:_:)`, the pass's keep a `Form`'s
rows use, here with `readsLayout: false`: the flattening reads neither the environment nor the width). It is kept
under the tree's first level, its rows' ids and which are branches (`_TableOutlineSource`), not under the table's
value: the stack's measure and its draw each ran the page's body, a quick one `BodyKeep` does not keep, so the draw's
table held new row-builder closures over the same rows, and a key of the value never matched. Within one pass the
app's state is the state the measure saw, so the same first level is taken to have the same rows beneath; across
passes the rows are built again, as before. `listed` halves, to `outline-rows`' counts at n and 10n:

| Case | Phase | Listed at n | Listed at 10n |
|---|---|--:|--:|
| `outline-rows-stacked` | `key:oright` | 10,002 → 5,001 | 100,002 → 50,001 |
| `outline-rows-stacked` | `wheel:+5` | 100,020 → 50,010 | 1,000,020 → 500,010 |
| `outline-rows-stacked` | `key:pgdn` | 30,006 → 15,003 | 300,006 → 150,003 |

**Cheaper to flatten (2026-11-16).** The flattening noted each row's place, parent and node in three dictionaries
keyed by its id, 16.5% of a frame of `outline-rows-stacked` in their stores. It keeps them in arrays parallel to the
rows now, and builds the one index by id the first time a row is asked for by id (a draw asks for the rows it draws);
a row modifier's traits are kept only once a row has some, and a branch's rows handed to an empty list are taken
rather than copied. Timed against the once-a-pass commit (`ab_bench.py`, release, cpu-per-frame): `outline-rows`
−15.8%, `outline-rows-stacked` −17.6%, `outline-table` −18.6%, `outline-list` unchanged; against the commit before
both, `outline-rows-stacked` −55.9% and `outline-rows` −16.2%. What remains is the row builders themselves (the
row-builder question above), and in them generic metadata lookups (`swift_getGenericMetadata`, 19–21% of the frame
inclusive, before and after) made by the unspecialised row content walk: a lead for another change.

**The walk's generic costs (2026-11-16).** Followed up in five commits, each timed against the one before
(`ab_bench.py`, release, cpu-per-frame, `outline-rows` / `outline-rows-stacked`): the outline's row places made
top-level types rather than generic ones nested in `_TableOutline`, and its stack split into a generic and a
non-generic half (−7.3% / −6.0%, and `outline-table` −11.6%); a `DisclosureTableRow` keeping its value rather than a
label it flattened to find it (−4.5% / −4.1%); a branch of plain leaves listed whole, with no node made or pushed
for each (−26.7% / −27.2%); a `ForEach` that reads ids directly no longer making a key path, which through a
protocol requirement is made from its pattern every time even in specialised code (−8.1% / −10.6%); and a loop of
rows walking an array's storage rather than a generic iterator boxed on the heap (−14.4% / −13.9%). Together:
`outline-rows` −47.3%, `outline-rows-stacked` −47.4%, `outline-table` −10.1%, the flat table scenarios unchanged.
Metadata lookups are still about a fifth of the shorter frame: per row in `TableRow`, `_ConditionalContent` and
`_TableRowList.append`, and in the draw's index of rows by id. Making the walk `@inlinable` would specialise it in the
app, but would put the row list's internals in the ABI; not done.

### G1-rows: why it is not fixed yet, and the options

A `Table(_:children:)` keeps its outline because it can tell its tree has not changed: one array buffer of values
whose children are stored in them (decisions B-FP2-5). A tree written as row content has no such test. The table is
made again in its parent's body on every pass that draws it (a write at the table, its own scroll included, drops
its ancestors' memo entries, so their bodies run), and with it every `DisclosureTableRow`'s content closure is new.
What a closure would build cannot be known without running it, and running it for every open branch is the cost.
Keeping the outline needs a rule for when the app's row builders would build the same rows, which is a contract
question, not an optimisation:

| Option | Rule | What it saves | Cost and risk |
|---|---|---|---|
| (a) Keep the whole outline | The plain-body memo's rule (decisions, "When a body runs"): the root rows compare equal field by field, closures ignored, while nothing at or above the table wrote since | Scrolls and the table's own cursor moves become a screenful | Needs a "written above since" signal the render cache drains but does not keep. Does not help tuitree: its `.selectionFollowsCursor()` writes the editor's `@State` on every cursor move, and its expansion bindings on every open, and after a parent's write a closure counts as changed (deviation S8) |
| (b) Keep each branch's rows | SwiftUI's rule for a `TableRowContent` struct: a branch's content value (`NodeRows`) equal field by field to the kept one keeps the kept rows | Every branch whose inputs did not change | The same S8 limit: `NodeRows` holds a `Binding`, opaque, so under a parent's write every branch is rebuilt; and a walk of every open branch is still linear, if far cheaper |
| (c) Window the rows | A `ForEach` of rows counts one row per element (SwiftUI's lazy containers assume a constant number of views per element), each open branch's subtree size kept from the last pass, and only drawn rows' content built | Every pass, tuitree's cursor moves included | Unsound where an element's content changes shape (a branch becomes a leaf, a filter in the closure) with its data unchanged: the row count and the keys' targets are stale until those rows are drawn. A large change to `Table`'s resolution, which reads `data` whole (type select, selection by id, `.fit` columns) |

Not chosen here: (a) leaves tuitree as it is, and (b) and (c) change what an app can rely on its row builders
for. The question for the owner: is (c)'s rule, SwiftUI's own for lazy containers, acceptable for table rows, or is
(b) with the walk made cheap the limit? Until then tuitree can draw its tree as `Table(_:children:)` over a tree of
values whose children are stored (not computed), which is windowed and kept today.

That workaround has a catch, found 2026-11-16 while putting the question to the owner: `Table(_:children:)` takes no
expansion of its own, as SwiftUI's takes none (`ListAndTable.md`, "A tree that starts open"), so its branches start
closed and only the user opens them. tuitree opens its root at launch and Find opens a match's ancestors from code;
on `Table(_:children:)` it could do neither. Hence a fourth option:

| Option | Rule | What it saves | Cost and risk |
|---|---|---|---|
| (d) Let the app own a `Table(_:children:)`'s expansion | A TUI-only modifier (`.outlineExpansion($openIDs)`, say), kept apart from SwiftUI's API as CLAUDE.md asks of TUI-only options; the row-builder contract is untouched | What `Table(_:children:)` saves today, for an app that must open branches from code | About a day in TUI. An API SwiftUI lacks, so a SwiftUI port goes back to `DisclosureTableRow`. The app builds a tree of values with stored children once per change, not per pass |

Put to the owner with (d) recommended, measured first: a cursor move in tuitree on its 3.2 MB file is timed before
anything is built, since `built` stays at a screenful and only `listed` grows, and the time the closure walk costs
there has not been measured.

**(d) chosen and built (owner, 2026-11-16).** Not as a modifier, as the row above first sketched it, but as CLAUDE.md's
new "Extending SwiftUI's API" section allows: a defaulted parameter on SwiftUI's own initialisers,
`expansion: Binding<Set<Value.ID>>? = nil`, after `children:` on all six `Table(_:children:)` forms (selection none,
single, set; each with and without `sortOrder:`). `nil` keeps the table's own expansion at its place, as before; a
binding is the only record, opened exactly as its set says and written by Right, Left, ⌥Right, ⌥Left and the
triangle's click. Every SwiftUI form is in the compile corpus, so each is seen to resolve as it did.

How it keeps the windowed path: the outline's expansion became one type with two stores
(`_TableOutlineExpansion`, the table's box or the app's binding), read once a flattening and once a key or click, and
written once a gesture (an ⌥Right over thousands of branches copies the app's set once, not once a branch). The kept
outline (`_TableOutlineCache`) compares the reading it was made from with the reading now, so an unchanged set, in the
same storage, keeps it; a change makes the outline again from the kept roots. Making only the changed branches again,
splicing their rows into the kept outline, was not done: the rows' parent links and branch indices shift with every
splice, and the outline is made once a change, as the table's own expansion already makes it, never once a frame.
`List(_:children:)` and `OutlineGroup` were not given the parameter: their expansion is the group's `StateBox` across
the list's windowed and section paths, and threading a binding through them is its own change, left as a follow-up.

`outline-children-bound` is `outline-table` with the app keeping the expansion (`outline.bound`), recorded on a clean
debug build: every count, at n and 10n, is `outline-table`'s (`key:oright` listed 0, built 21; `wheel:+5` built
158, served 60), so the binding costs the windowed table nothing the counters see. Its page shares
`outline-table`'s arm of the case's `switch` (`expansion:` `nil` there): an arm of its own, as first written, nested
the other arms a level deeper and raised `outline-rows-stacked`'s `misses` by about one a frame (`open` 81 → 84,
`wheel:+5` 270 → 280), the harness's shape and not the table's, as the comment on `CaseOutlineView` already warned.

The follow-up landed on 2026-11-17: every `List(_:children:)` and view `OutlineGroup` initializer takes the same
defaulted `expansion:` (`OutlineExpansion`, the outline's box or the app's binding, read once a pass and once a key,
and compared by the kept rows, `OutlineVisibleNodes`, as the table's outline compares its reading). Two cases are
`outline-list` and `outline-section` with the app keeping the expansion, `outline-list-bound` (`outline.list.bound`)
and `outline-section-bound` (`outline.section.bound`), each sharing its twin's arm of the `switch` for the reason
above. Recorded on a clean debug build, every count at n and 10n is the twin's (`key:oright` listed 22, built 21;
`wheel:+5` listed 220, built 165, served 63), and no other recorded line moved.

## Lane 5, as built (2026-11-16)

**The documentation.** The `Stress` README's "Perf cases" section is the reference for writing, checking and
re-recording a case, written from the code rather than from this design; the Profiling README's A/B section prices a
timed case; `CONTRIBUTING.md`'s "Performance tests" says when to add a case and when to mark it `timed` (the table
under "Choosing between counting and timing for a case", above).

**The timing trend** (A-PERFCASE-3): `Tools/Profiling/perf_trend.py`, with its tests in `test_perf_trend.py`.

| Design | As built | Why |
|---|---|---|
| A sweep of the `timed` cases appends its rows | The script appends what a saved `ab_bench.py` output holds, and runs nothing | Timing is the scarce resource: a run already made is read, not paid for twice. `ab_bench.py`'s table is the one timed run there is; `sweep.py`'s CSV is a survey of 3 short reps, too coarse for a trend |
| Commit, toolchain, machine, load, µs, interval | Date, commit, machine, load, metric, scenario, iterations, median µs, interval, RSS; no toolchain | The output names no toolchain, and the commit is given with `--sha` (default `HEAD`). The metric (`cpu`, `wall`, `-cold`) keeps readings of different kinds apart |
| The interval of the reading | The interval of the change against the run's base, as `ab_bench.py` printed it | `ab_bench.py` bootstraps the paired ratio and prints no interval of an absolute time. Its width is that sitting's noise |
| A case that drifted past its noise floor against the median of its last five readings is flagged | `--report` prints the last N readings and the latest's change from the first, `within` or `beyond` the widest interval among them | The interval is a paired one; readings from different days are not paired, so `beyond` is a prompt for an A/B of the two commits, not a flag of a regression |

## Lane 4, the first part (2026-11-17)

Forty cases over situations nobody had counted, in six new tables and two more rows of `Editors.swift`. This lane
measures: what broke a case's class is filed below as a finding and named in `CaseKnownIssues`, not fixed.

| Table | Cases |
|---|---|
| `Presentations.swift` | `sheet-present`, `sheet-search`, `sheet-item-switch`, `sheet-item-walk` (W17's kept items, a walk past the 16), `popover-values`, `alert-list`, `alert-table`, `sheet-tiny` |
| `Navigation.swift` | `tabs-kinds` (a list, a wrapped table, the value controls and a grid as tabs), `tabs-lists`, `nsplit-resize`, `nsplit-collapse` (under 21 cells, into a stack), `nsplit-three` |
| `Narrow.swift` | `list-tiny`, `table-narrow`, `table-fit-tiny`, `split-tiny`, `form-narrow`, `chat-tiny`, `editor-tiny` (40x12 and 20x6) |
| `Controls.swift` | `grid-scroll`, `grid-edit`, `form-grouped-tab`, `form-columns-tab`, `focus-tab-200`, `focus-tab-scaling`, `values-stepper`, `values-slider`, `values-date`, `form-slider`, `menu-walk` |
| `Pointer.swift` | `table-hover`, `split-hover`, `outline-hover`, `tabs-hover` (focus follows the pointer) |
| `Storms.swift` | `resize-storm` (a list beside tabs of a table and a grid), `nsplit-storm`, `dashboard-storm` (the `dashboard` scenario, adopted) |
| `Editors.swift` | `editor-mid-typing` (300 lines in 80x24), `editor-sheet-typing` |

**Timed:** `resize-storm` and `dashboard-storm` (a resize redraws every cell, which no count weighs),
`editor-mid-typing` (a keystroke's cost is in the text storage and the wrap) and `form-grouped-tab` (a form's
constant factors, PERFCASE-F7, are what a user feels).

**The vocabulary it added**, written once and used by the rows: the leaves `grid`, `form.grouped`, `form.columns`,
`controls`, `values` and `menu` (`CaseControlView.swift`); the combinators `sheet(a,b)`, `sheetitem(a,b)`,
`popover(a,b)`, `alert(a)` and `nsplit(a,b[,c])` (`CaseCombinedView.swift`); and the steps `present`, `dismiss`,
`item:i`, `item:+k` (writes to what a presentation is bound to) and `resize:±Wx±H` (a window dragged at its corner:
`resize:-16x-5*5;resize:+16x+5*5` is a storm of ten). Each new arm shares an existing one of the switches that draw a
page (a `default:` handing off to a view of its own), since an arm of its own deepens the conditional content the
others sit in and moves their misses (as `CaseOutlineView`'s comment warns): every one of the sixteen earlier cases
plays exactly its recorded counts.

**What the scripts first did wrong**, each seen in the counts (0 bytes) and fixed before recording: a Tab in a sheet
moved the focus out of the search field it opens in; the stepper answers Right and Left, not Up and Down; the first Tab
in a three-column split lands on a divider; after a hover in a scene whose focus follows the pointer, Right is the
content's, not the tab strip's; and 200 Tabs through 200 buttons came round to the first, so the rerun at 2n scrolled
elsewhere. Three `linear` cases first failed for the case, not the code: in `tabs-kinds` at n = 100 and
`focus-tab-scaling` at 60 the fixed work was a fifth to a third of a count, which at 2n is then neither the same nor
twice (their n was raised), and `grid-scroll`'s 50 wheel ticks reached the end of 100 rows but not of 200.

Each case's n is also what `--selfcheck` plays its session at, 150 steps against a cache-cleared twin, so a case of an
eager control is kept small: `tabs-kinds` first held a form's tab (PERFCASE-F7) and took 95 s there, debug, then a
grid's, whose fixed work kept `linear` from holding at any n the selfcheck could afford, and holds the value controls
and an editor now, `flat`; the forms are 5 and 10 rows, the splits 300 to 500.

**Findings** (filed, not fixed here; the numbers are at n, then at 10n):

- **PERFCASE-F6. A `NavigationSplitView`'s leading columns are not windowed.** `nsplit-resize` (300 rows) lists 1,389
  row boxes, runs 2,819 bodies and misses 7,786 measures as it opens (12,194 / 24,429 / 72,611 at 10n), and about n
  of each at every resize. `measureColumns` (`NavigationSplitViewWidths.swift`) measures each leading column offered
  no width and no height, to read its hugged width, and a `List` offered no height lists, runs and measures every row.
  Collapsed into a stack it is O(window) (`nsplit-collapse`'s `resize:20x12`: 66 boxes at n and 10n). `nsplit-three`
  pays it in both leading columns; `nsplit-storm` at every resize the split is not collapsed. (At 200 rows
  `nsplit-storm` built twice the rows it builds at 2,000, under the 256 rows a list builds whole; it plays 300.)
- **PERFCASE-F7. A `Form` lays out every row on every frame.** `form-grouped-tab` (10 toggles under the value
  controls) runs 559 bodies and misses 2,486 measures a Tab (4,564 / 21,258 at 100 toggles): about 45 bodies and 209
  misses per toggle per frame, every row's body run and measured, none served. A slider step pays the same
  (`form-slider`), and so does toggling one toggle (`key:space`). `.columns` is about a third of `.grouped`. A macOS
  form is a list, windowed; this one is an eager stack. The cases keep n at 10 for what it costs the check.
- **PERFCASE-F8. A `TabView` measures its hidden tab at every narrowing resize.** `resize-storm`'s hidden tab is a grid
  of n rows: it runs 2,896 bodies as the page opens (24,496 at 10n), as `tabs-switch`'s hidden table reads its cells,
  and 8,584 over the five narrowing resizes (78,798 at 10n), each of which also asks for a second frame; the five
  widening ones run 598 (606). Not seen: why narrowing re-measures every tab and widening does not.
- **PERFCASE-F9. A menu rebuilds every item at every arrow key.** `menu-walk` builds 808 rows over 20 Downs in a menu
  of 40 items, 1,608 in one of 80: the whole menu a step, not the two rows the highlight moved between. The case is
  `linear` (a menu's items are made when it opens), so its class holds and only the count says so.
- **PERFCASE-F10. A hover over a table rebuilds its visible rows.** In a scene whose focus follows the pointer,
  `table-hover` builds 328 rows and reads 4,900 cell values over 20 one-row hovers (about 16 rows and 245 cells a
  step, every row on the screen), where `list-hover`'s list builds 6 and serves 440: a table's cursor row is drawn
  into its rows, not over them. Flat in n; `tabs-hover` and `split-hover` show it too.
- **PERFCASE-F11. A searchable `List` in a sheet builds every row as the first keystroke filters it.**
  `sheet-search`'s `type:ab` builds 524 rows of 500 (5,024 at 10n), where `list-search`, the same list on a page,
  builds 45; the backspaces after it build 2. Not seen: what about the first filtering in a sheet asks for every row.
- **PERFCASE-F12. A few counts move by a constant at 10n.** `list-tiny` misses 4 more measures as it opens in 20x6
  (359, 363), `split-tiny` 4 fewer at its resize (384, 380), `resize-storm`'s narrowing resizes list and build 7 more
  rows (425, 432) and `nsplit-three` builds 2 more as it opens; a wrapped table reads 1,115 cell values as it opens
  at 500 rows (`sheet-search`), 1,125 at 1,000 (`sheet-item-walk`) and 1,135 from 2,000 on.
  None grows with n; their causes are not seen.
- **PERFCASE-F13. A list row behind a popover presented a second time is drawn a cell off.** With `;key:esc` at the
  end of `popover-values`' script, its session's loop presents the popover again, and from the Tab after that the
  first list row below the popover is drawn with its status one column left of where the cache-cleared twin draws it,
  on every frame: `Stress --session case:popover-values --steps 150 --verify --resize-every 37` fails 105 of 150
  frames, from step 14 (14 of 30 with no resizes). A memo serves that row, or its size, from before the second
  presentation. Found by `--selfcheck`'s verifier, not by a count; the case's script stops before the Escape until it
  is fixed, so the gate's `--selfcheck` passes, and the fix puts it back. **Fixed (2026-11-17):** not a row but the
  whole list, and its layout: under `.scrollIndicatorPlacement(.overContent)` a list places its scrollbar beside its
  rows while it holds the focus, and over them while it does not. Presented, the popover activates its section with
  nothing focused, and the list, drawn that frame, finds no focus to ask about and keeps what it last decided
  (`focusIsWithin`): the bar beside, the rows a cell narrower. Its drawing was stored, whole, in the value memo of the
  view around it. The Tab into the popover moved the focus from nothing to its first control, and a focus move drops
  the drawings of the controls at either end of it, which from nothing is only the one it lands on: the list's stored
  drawing went on being served. Why the first presentation does not show it is not established. Now a view that
  answers from what it last knew is noted by the focus manager with its answer (`noteDrawnAwaitingFocus`), and the
  next focus move drops its drawings and those containing it where the answer was wrong: the focus landed outside a
  view that drew as if it were inside (`FocusManager+UnlandedFocus.swift`). A view the focus lands in is dropped
  already, as the destination's ancestor; dropped again, as a first try did, a `.fit` table beside the list that
  takes the first focus read 5 cells more as `split-resize` and `nsplit-storm` open. The case's counts moved where
  the stale list had been served: its Tab now lays the list out again for a bar over the rows (21 rows listed, 919
  bytes, where 74 bytes wrote nothing of the list), and each Right lists the visible rows again and serves them from
  their row memos (168 listed and 170 served over ten, where the stale list was served whole). Why the list laid out
  again is not served whole on the Rights is not established. `PresentedAgainCacheTests` plays the script against an uncached twin, one
  frame a step, for a popover, a sheet, an alert and a confirmation dialog: the popover failed from the second Tab,
  the other three did not; all four pass. The case's script has its Escape back.

Known already and named for the new cases: a `.fit` column reads every row as its table opens (PERFCASE-F5's class,
`alert-table`, `table-fit-tiny`, and `nsplit-storm`'s resizes), and the bottom-anchored lazy stack's PERFCASE-F3
(`chat-tiny`).

**What held.** Sheets, item sheets, popovers and alerts cost the rows on screen, at n and 10n: presenting
`sheet-present`'s list over a list builds 92 rows and writes 102 bytes, and an item switched back to (`item:1#2`)
builds 63 and writes 36 bytes, its scroll as it was left (W17). An alert over a `.fit` table reads 557 cell values,
not the 10,000 of its columns. Typing in a 300-line editor, in a sheet or not, is the same at 3,000 lines. The value
controls, the tiny list and table, the windowed tabs and every hover are flat.

**What they cost**, debug, on the development machine while other lanes built and tested. `--check-counts`: the
sixteen earlier cases 28 s, the forty about 80 s, `focus-tab-200` 15 s of it (199 frames of 200 buttons, which is why
it is not rerun at 2n and `focus-tab-scaling` checks its class) and the form and split cases at 10n most of the rest
(PERFCASE-F6 and F7). `--selfcheck`: their sessions, each 150 steps against its cache-cleared twin, about 4 min
(244 s; `nsplit-storm` 27 s at 200 rows and 9 s at 300, `dashboard-storm` 14 s, `form-grouped-tab` 14 s,
`focus-tab-200` 13 s), of a whole selfcheck of 31 min; their pages at rest, seconds.

## For a future reader

- Counts are proxies. A clean `--check-counts` says the work did not change, not that the time did
  not. The copying accumulator of 2026-08 kept every call count linear. Keep the timed sweep.
- Before trusting a counter, break the thing it guards and watch the check fail. Tests that pass
  without their fix have recurred here (the review of 71 commits on 2026-11-07 found the pattern
  more than once).
- A re-record that raises a count deserves the question a reviewer would ask: what does the case
  now do that it did not do before? The commit message is where the answer lives.
- The table is an index of situations someone thought to ask about. A case nobody wrote is still
  unmeasured. L4's list of situations is a start, not a census.
- The `timed` set is chosen, and the choice dates. When a counted-only case turns out to be where
  time goes, mark it `timed`, and say so in the commit.

## The record

### B-PERFCASE-1. A case is a row in a table, over a vocabulary written once

Compositions, containers, sizes, counts and scripts are named values in Swift enums. A case is
one line that combines them. A new composition or step is Swift code, written once and then used
by every row.

### B-PERFCASE-2. Every case is counted; only `timed` cases are timed

Counting is cheap and deterministic, so it covers the whole table on every landing. Timing needs
about 90 s per case on a quiet machine, so it is spent on the cases where counts cannot see the
cost (the table under "Choosing between counting and timing for a case").

### B-PERFCASE-3. One harness: cases run as `Stress` sessions and variants

A case with a script plays through a generic `CaseSession`. A case without one is a variant of a
`cases` matrix scenario. No new runner and no new target. The existing tools read cases off the
binary as they read scenarios now. (Subject to A-PERFCASE-2.)

### B-PERFCASE-4. Counts are recorded, re-recorded on purpose, and explained in the commit

The recorded file is the expectation, exact (A-PERFCASE-1). A rise fails. A fall is an
improvement and passes, but `--check-counts` prints it with both numbers (`IMPROVED tall-table
built 4,153 → 20`) on every run until it is re-recorded, so an improvement is quantified rather
than lost. `TUI_RECORD_PERF_COUNTS=1` re-records, and the commit says why. Every case is counted
twice in one run and fails if the two differ: a count is deterministic, so a difference is
flakiness, which exact counts exist to catch.

### B-PERFCASE-5. Case ids and descriptions are English only

They are a development tool's own listing, as variant summaries are (`ScenarioVariant`). The
`cases` matrix scenario has one translated title, and no case adds a string to a table.

### B-PERFCASE-6. A bodies-run counter joins `RowWork`

It is an increment on `RenderCache`, which is a class, not a field carried in `RenderContext`. It
is priced with `ab_bench.py --quick` when it lands, and it closes the gap `ab_counters.py` names.

### B-PERFCASE-7. A scaling class is checked by running the case again, not by recording it twice

`flat` reruns a case at 10n and requires equal counts. `linear` reruns it at 2n and requires
twice the counts, ±10%. The class survives a change of constant that a recorded number would
not, and it states what the case is for.
