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
| `composition` | What the page is built from: a name from `CaseComposition`, with dotted options | `list.plain`, `list.search`, `table.fit5`, `table.wrap5`, `chat.lazy`, `chat.eager`, `editor.wrap`, `tabs(list.plain,table.fit5)`, `split(list.plain,table.fit5)`, … ; `stress:<scenario>[/<variant>]` adopts an existing one |
| `in` | The container around it: `CaseContainer`, a superset of `ScrollFitSituation` | `alone`, `title` (in a `ScrollView` under a title), `bottom` (bottom-anchored `ScrollView`), `sheet`, `fixed`, `-` for an adopted scenario |
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

Proposed 2026-11-14; the owner answered A-PERFCASE-1 to 3 the same day. Nothing is built yet. B-PERFCASE-1 to 7
are decided here and stand unless the owner's answers change them.

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
