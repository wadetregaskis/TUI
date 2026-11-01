# TUI against SwiftTUI

Measures TUI against [SwiftTUI](https://github.com/SwiftTUI/swift-tui) with the same small programs, so progress can be
compared after optimising. It's not part of the root package and adds nothing to a client's build.

The reports this produced are in `Documentation/Historical/SwiftTUI comparison, 2026-11/`. That folder holds what the
numbers meant at the time. This one holds what it takes to get the numbers again.

## Running it

From a checkout on macOS, with [swiftly](https://www.swift.org/swiftly/) and Swift 6.4.0, because SwiftTUI's manifest
needs 6.4:

```sh
python3 Tools/SwiftTUIComparison/comparison.py run --out ~/comparison-results
```

That measures TUI at `HEAD` and SwiftTUI at the pinned commit, `207913d23`. It prints the tables at the end. The whole
set takes about two hours on a quiet machine, once built, and a clean build of both takes 10 to 20 minutes more.

Useful options:

| Option | What it does |
|---|---|
| `--tui-commit C` | Any commit of this repository |
| `--swifttui-commit C` | Any commit of `SwiftTUI/swift-tui`; a full SHA fetches shallowly |
| `--frameworks tui` | Measure only TUI, and compare against the baseline's SwiftTUI |
| `--phases tree,scroll` | Only those phases |
| `--only tree-leaf,hello` | Only those scenes within the phases |
| `--runs 1 --presses 10` | Fewer runs and inputs, for a look |
| `--scratch DIR` | Sources and builds, by commit. The default is `tui-swifttui-comparison` in the temporary directory, outside the repo. Each framework's build is about 1 GB, and nothing deletes it for you |
| `--memory-limit-gb N` | Kill a measured program past this footprint: 8 by default, 0 for no limit |
| `--toolchain system` | The `swift` on `PATH` rather than swiftly's 6.4.0, for TUI alone at an older compiler |
| `--dedup`, `--large` | In the size phase, also relink with `-Xlinker -deduplicate`, and also build each framework's large example |

Then, to compare with the committed baseline, or any two runs:

```sh
python3 Tools/SwiftTUIComparison/comparison.py compare Tools/SwiftTUIComparison/baseline/summary.json ~/comparison-results
python3 Tools/SwiftTUIComparison/comparison.py compare OLD NEW --framework tui
python3 Tools/SwiftTUIComparison/comparison.py table ~/comparison-results
```

Builds go through `Documentation/Working notes/plan/slot.py` where that exists, so they wait for a build slot on the
machine it serves. A run prints which it found. Elsewhere builds just run. Measuring takes no slot, so it says nothing
to other work on the machine; for timings you want, get a quiet box first.

`run` and `strict-safety` need macOS. `table`, `compare` and `census` work anywhere, and so does the test:
`python3 -m unittest discover -s Tools/SwiftTUIComparison`.

## What to trust

| Measure | Trust |
|---|---|
| Allocations (`alloccount.c`) | Repeat to about 0.1% between runs, on a loaded machine. The thing to read first |
| Bytes written to the terminal | Repeat exactly for the same frame |
| Sizes | Exact for a given compiler |
| CPU time, from `proc_pid_rusage` | Fairly steady under load, not exact |
| Key-to-frame latency, frames per second, first frame | Need a quiet box. Compare within one table, not across runs at different loads: every scene states its load |
| Build times | One run, and rough. CPU time steadier than wall |
| Instruction counts | Not recorded: `proc_pid_rusage` returned 0 on this VM |

The malloc counter does not move the timings: with and without it, 115 to 123 against 116 to 118 ms for SwiftTUI, and
1.6 to 1.7 ms either way for TUI (2 runs of 20).

Allocations and bytes are net of what the program does while idle, at the rate measured just before. So a slow frame
during which a focus pulse stops overcorrects a little: `slow-sibling` on TUI reads about zero, even slightly negative.

A `*` in `compare` marks the measures that repeat. These are synthetic scenes, written once for both frameworks, so they
show how an engine scales and not how a real app feels.

## What each phase measures

The terminal is a 200 × 50 PTY the driver controls, answering queries as Ghostty does (`pty_driver.py`). Key latency runs
from writing the key to the marker's bytes reaching the driver. What a program does anyway, such as a focus pulse, is
measured first and subtracted from bytes, allocations and CPU, so a measure doesn't depend on the program going quiet. The
views are one source, `Benchmark/Common.swift`, compiled unchanged against both frameworks, apart from `Table`, whose API
differs (`Benchmark/TUIShim.swift`, `Benchmark/SwiftTUIShim.swift`).

| Phase | Scenes | What it shows |
|---|---|---|
| `tree` | `tree-leaf`, `tree-obs`, `tree-root`, `tree-all` | One key press in a 48 × 40 grid of `Text` built with `ForEach`: a leaf's `@State`, an `@Observable` read by one leaf, `@State` at the root, every cell changing |
| `scale` | `tree-leaf`, `tree-root`, `list-data`, `table` | How those grow, from 40 to 1,920 cells and 100 to 100,000 rows. SwiftTUI stops at 10,000 list rows and 1,000 table rows, which take minutes and gigabytes |
| `fan` | `fan-leaf` | A leaf beside a static tree with no `ForEach`: what a frame costs when no row memo is in the way |
| `siblings` | `slow-sibling`, `slow-sibling-parent` | Siblings whose `body` takes 50 ms and whose inputs never change: a retained graph's own case |
| `lists` | `list-data`, `list`, `table` | The Down arrow in 10,000 rows in a `VStack` with no stated height. This is the case that reached 25 GB in SwiftTUI, so expect the guard to end it |
| `lists-framed` | `list-framed`, `table-framed` | The same with `.frame(height: 44)`, at 1,000 to 100,000 rows |
| `scroll` | `scroll`, `scroll-varied` | Wheel notches over `ScrollView { LazyVStack }`, with rows that look alike and rows that share nothing: bytes, and whether a scroll region carried them |
| `latency` | `lat-slowbody`, `lat-heavy`, `lat-blend` | Key to frame while a 16 ms ticker keeps the program busy: a slow body, every cell changing, 30 blended layers. SwiftTUI's `SWIFTTUI_RENDER_MODE` is its own switch, so `async` against `sync` tests its off-main tail |
| `deep` | `deep-plain`, `deep` | `VStack` in `VStack`, without and with `AnyView`, doubling the depth until it fails. Each failure is recorded by how it failed |
| `anim` | `anim-opacity`, `anim-move`, `anim-tick` | A screen of cells animating: frames, bytes and CPU |
| `idle` | `hello`, `counter`, `big-tree`, `counter-companion`, `counter-reduce-motion` | 20 s of nothing: CPU, wakeups. TUI's focus pulse and SwiftTUI's attach poll show here |
| `memory` | `hello`, `big-tree`, `list-10k`, `list-100k`, `table-10k` | Footprint once the first frame has settled |
| `frame-trace` | `lat-blend`, `lat-heavy` | SwiftTUI's own trace: frames committed, cancelled and dropped in each render mode |
| `size` | `hello`, `counter`, `listsel`, `midapp` | Stripped size. TUI on the `TUI` product and on selective modules; SwiftTUI on its default and terminal-only products. It runs last, because `--dedup` relinks the small apps |

## The other two commands

`census` counts every `@unchecked Sendable` and `nonisolated(unsafe)` in `Sources` by the reason it's there. The reasons
are assigned by the declaration's name, so a new declaration comes out `UNCLASSIFIED`: read that list, and add to the
tables in `census.py`. Comments don't count.

`strict-safety --out DIR` type-checks each module of TUI at a commit with `-strict-memory-safety` (SE-0458), against the
modules a release build made, and counts the diagnostics by module, kind and cause. Nothing in the source changes. A
module the benchmark's build doesn't reach, `TUIFilePanelsAppKit` today, shows a setup error instead of a count.

## The baseline

`baseline/summary.json` is the first run: TUI `3d605c2c4`, SwiftTUI `207913d23`, Swift 6.4.0, an Apple M4 Max VM of 14
cores and 32 GB on macOS 15.8.1, on 2026-10-31 and 2026-11-01. It was made by an earlier form of these scripts, and its
`meta.notes` say how it differs. Its `meta` also holds that run's census and strict-safety counts, for the same commit.
Each scene has its run count and load, the later fairness scenes ran under load 16 to 69, and the rest mostly 4 to 8. So
when a later run's timings look better, check those columns before believing them. Its allocations and bytes are firm.

A later run that should replace it: copy its `summary.json` here, with a note in the commit of what changed.
