# Profiling TUI

Tooling for CPU-profiling TUI with Instruments' **Time Profiler**, from
the command line, with the results parsed into a ranked list of hot
functions. No GUI, no external Python packages — just the macOS toolchain
(`xcrun xctrace`) and the Python standard library.

## Why this exists

TUI's render pipeline is `@MainActor`-isolated, which blocks the
`ordo-one/benchmark` suite from measuring whole-view rendering (it traps
on a main-thread `DispatchSemaphore`; see
`Documentation/Performance/Benchmark coverage and deferred MainActor benchmarks.md`).
Instruments has no such limitation — it samples whatever thread is running,
and never needs to block the main actor to take a measurement — so the Time
Profiler can measure the real render path end to end. This directory makes
that repeatable.

> Do not read that as "the main thread *is* the main actor", which this
> README used to claim. It is false on Linux: from the first suspension
> point onward the main actor is drained by a cooperative pool thread, not
> the process main thread (measured; see the "Thread correctness" note in
> `Sources/TUICore/Concurrency/StackGuard.swift`). Profile by sampling
> the process, not by assuming which thread the render is on.

## Two profiling modes

| Mode | What it profiles | Status |
|------|------------------|--------|
| **B — end-to-end (this toolkit)** | The real `Example` driven through a PTY: input → 5-layer dispatch → render → diff → `write()` | ✅ working |
| **A — headless render harness** | `renderToBuffer(view:)` on fixed view trees in a tight loop — deterministic, fully CPU-bound, no input timing | ✅ working (`RenderHarness`) |
| **A′ — headless image harness** | `ASCIIConverter` over a picture, per cell and per pixel separately | ✅ working (`ImageHarness`) |

Mode B is the realism check. Mode A is the microscope for iterating on a
fix; it pairs with the existing `TUI_BENCHMARKS=1 swift package benchmark`
malloc/CPU counters for regression guards (benchmarks are opt-in behind the
`TUI_BENCHMARKS` flag).

> **`--attach` vs `--launch`.** Mode B has `drive.py` fork the app in a
> PTY and points `xctrace record --attach <pid>` at it. Some environments
> deny debugger attach entirely ("Not allowed to attach to process" — CI,
> locked-down VMs, sandboxes); there, Mode B cannot record. Mode A's
> harness needs no PTY, so Instruments can **launch** it
> (`xctrace record --launch -- RenderHarness …`), which those environments
> do allow. When attach is blocked, Mode A is the only profiling option.

## Prerequisites

- macOS with Xcode / Command Line Tools (`xcrun xctrace` — Instruments).
- `python3` (standard library only).
- Run from the repository root.

> Recording attaches Instruments to your own process; no `sudo` needed
> for locally-built binaries. The first run may prompt for Developer
> Tools access.

## Quick start

```bash
# Build (release+symbols), drive a scenario, record, and print hot functions:
Tools/Profiling/record.sh                 # 'tour', 15s, 50x160
Tools/Profiling/record.sh emoji 20        # hammer the 1212-row emoji list
Tools/Profiling/record.sh idle 12         # steady-state per-frame cost
Tools/Profiling/record.sh list 15 24 80   # List page in an 80x24 terminal
```

Traces land in `profiling-traces/` (git-ignored).

## What a page costs to ARRIVE — `page_open.py`

`drive.py` measures a scenario running; this measures a page arriving, which is
what "slow to open" means. It resets the menu cursor, opens item *i*, and reads
until the output has been quiet, reporting wall time and bytes per round — in
ONE process, so a cost paid once per page per session shows up as round 0 and
nowhere else.

```bash
Tools/Profiling/page_open.py .build/release/Example 1,13,20 --rounds 4 --cols 200 --rows 50
PROBE_HOST=Apple_Terminal Tools/Profiling/page_open.py .build/release/Example 1
```

`PROBE_HOST` sets `TERM_PROGRAM`, which selects the per-host compensation walks
in `FrameDiffWriter` — those run only in emission, so `Stress --bench` cannot
see them. An animated page never goes quiet and reads as the `--quiet` cap;
that is a limit of the oracle, not a measurement.

## Deciding whether a change actually helped — `ab_bench.py`

Profiling says *where* the time goes. Deciding whether a change moved it is a
separate, and surprisingly easy to get wrong, question:

```bash
swift build -c release --product Stress && cp .build/release/Stress /tmp/old
# …make the change…
swift build -c release --product Stress && cp .build/release/Stress /tmp/new
Tools/Profiling/ab_bench.py /tmp/old /tmp/new                    # every scenario, ~1 h
Tools/Profiling/ab_bench.py /tmp/old /tmp/new --quick            # six of them, ~4 min
Tools/Profiling/ab_bench.py /tmp/old /tmp/new --scenarios fanout --reps 40
Tools/Profiling/ab_bench.py /tmp/old /tmp/new --cold             # all-miss frames
```

**The scenario list comes from the binary**, not from this script — a hard-coded
list goes stale silently, and did: `menus` and `gradients` were added to
`Stress` and never added here, so every "full sweep" for weeks quietly skipped
the only scenario with a `Menu` in it. Which is the same failure the `menus`
scenario was written to fix. `animating` and `translucent` are still excluded by
name: both are driven by the harness's frame counter, so a fixed-iteration run
measures a different mix of in-flight work each time — ask for them explicitly
when the question is about animation or compositing.

**`--quick` is for iterating**, not for deciding. Six shapes — `deep`, `fanout`,
`menus`, `modifiers`, `anyview`, `framedcolumns` — at 12 reps: a deep tree, a
wide eager one, styled controls, modifier chains, type erasure, and an ordinary
page. Measured null test (one binary against a copy of itself, 12 reps):

    deep -0.2% [-0.8, +0.8]      fanout    -0.3% [-0.8, +0.3]
    menus -0.5% [-1.0, +0.4]     modifiers +0.2% [-0.5, +0.4]
    anyview -0.2% [-0.8, +1.0]   framedcolumns -0.4% [-1.8, +1.0]

So it resolves ~2% and up. Anything smaller, or anything you are about to
commit, gets the full sweep.

`--cold` resets the state store and render cache before every frame, so nothing
is ever served from a cache. (Before 2026-10-08 it replaced them without
emptying the old ones, which kept each frame's whole render alive — see
`Sources/Stress/README.md` — so cold numbers from before then are not
comparable with later ones.) The default (warm) run measures the steady state an
app spends its life in; `--cold` measures the other end — the first frame of a
page, and, more to the point, **the honest check on any change that trades a
cheaper cache hit for a dearer miss.** Run it whenever the change touched what
happens on a miss.

It prints a change, a 95% interval and a **verdict** per scenario:

```
scenario           iters     old µs     new µs   change           95% CI  verdict
modifiers           1077     1154.7     1492.3   +29.9%    +28.2%  +31.0%  slower
fanout               349     4724.5     4463.0    -5.7%     -6.7%   -2.2%  faster
anyview              727     1974.2     1996.2    +0.5%     -3.2%   +3.1%  indistinguishable
```

`indistinguishable` is the answer that matters. Two changes were committed and
reverted on 2026-08-12/13 (§31 and §33 of
`Documentation/Performance/Full performance profile of Stress and the Example (2026-08).md`) because a hand-rolled A/B gave
them a number with a sign where the honest answer was "cannot tell".

Four things make it trustworthy, and each was validated by measurement:

| | |
|---|---|
| **CPU time, not wall clock** | Reads the harness's `cpu-per-frame`. Preemption by everything else on the box no longer lands in the number. |
| **RAM beside CPU** | Reads the harness's `rss-peak` and prints `ram OLD->NEW` after the verdict. Plain medians, not a bootstrap: peak RSS barely varies between runs of one binary, so an interval on it would be theatre. A change over a megabyte is worth a look; below that it is allocator noise. |
| **Randomised run order** | A fixed order is a fixed bias — every hand-run pass showed whichever binary ran *second* as slower, including the pass where that was the original. |
| **Paired ratios + a bootstrap CI** | A and B run adjacent in time, so drift hits both; comparing per-rep ratios cancels it, and the interval prices what is left. |
| **Calibrated iteration count** | 300 iterations of a 160 µs scenario is 50 ms of measurement, mostly warm-up. Each run is sized to ~4.5 s (1.5 s with `--quick`). |

**Noise floor** (identical binary against a copy of itself, machine at load
1.7 with a browser taking 27% of a core): `dashboard` ±0.7%, `table` ±1.7%,
`churn` ±2%, `fanout` ±3% at the then default 15 reps of 1.5 s and ±2% at 40. Run the null
test yourself — `ab_bench.py X X` — whenever you doubt a result; it costs one
command and tells you exactly what this machine can resolve today.

**The Table scenarios** (null test at 20 reps, 2026-09-21, quiet machine):
`table-churn` ±0.4%, `table-churn-wrapped` ±0.4%, `table` ±0.6%,
`table-multiline` ±0.5%, `truncate` ±1.0%. All five resolve a one-percent
change, which they need to: they are the corpus for the question of whether
`Table` should memoise its rows, and the counters in the `rows` / `cells`
column of a sweep move long before the clock does.

**Some scenarios cannot resolve anything small.** `megalist` and
`tables-vstack` null-test at **±15%** on this machine — their own run-to-run
spread swamps any change worth making. Both produced spurious verdicts on a
change that was fine (`tables-vstack` "+3.7% slower", `megalist` "+7.8%"), and
the null test is what exposed them. Check a scenario's floor before trusting
its verdict.

**One false positive per sweep is expected.** Seventeen scenarios at 95%
confidence means roughly one verdict per run is wrong by chance. Treat a
`faster`/`slower` whose interval *edge* sits on zero as a prompt to re-test —
`--reps 40 --seed <something else>` — not as a result. That is exactly what
happened to `table` in commit 114f7fa9: +0.7% [+0.0, +1.6] "slower" on the
first pass, +0.5% [-0.1, +1.0] indistinguishable on the second.

**Two tuning knobs that measured worse, so they are not options:** taking the
minimum of several runs per binary per rep (widened `fanout` to ±5% — the min
is a biased estimator whose bias tracks the local noise, and the extra runs
push A and B further apart in time, weakening the pairing); and shorter runs
with proportionally more reps (helped `churn`, hurt `fanout`, which needs
enough frames to amortise process start-up).

**Longer runs, fewer reps** is the knob that did pay, and why a run is 4.5 s
and a sweep 10 reps (2026-10-27, the owner's suggestion). Null tests of one
binary against itself on `keyrows`, `menus`, `stateful`, `table` and
`geometry`, mean 95% interval width:

| run × reps | time per binary per scenario | mean width | false verdicts |
|---|---|---|---|
| 1.5 s × 15 (the old default) | 22.5 s | 4.3% | 1 of 5 |
| 1.5 s × 30 | 45 s | 4.3% | 0 of 5 |
| 3 s × 10 | 30 s | 1.9% | 2 of 5 |
| 4.5 s × 10 (two rounds) | 45 s | 2.4%, 2.5% | 0 of 10 |
| 7.5 s × 6 | 45 s | 2.5% | 0 of 5 |

Doubling the reps at 1.5 s bought nothing; tripling the run length halved the
interval. A burst from something else on the box lands on one binary's run,
and a longer run averages it into the rest; process start-up is spread over
more frames too. `3 s × 10` looked tighter still, but two of its five null
tests came back `faster`/`slower` at the edge of a narrow interval — chance,
or a bootstrap of ten short runs claiming more than it knows — while
`4.5 s × 10` gave none in ten, so the longer run is the default.
The full sweep takes twice as long as it did, about an hour.

## `ab_bench.py` is blind to the whole output half — `emit_bench.py`

`--bench` is a counted `renderToBuffer` loop with **no PTY**. Everything
downstream of the frame buffer therefore never runs:
`FrameDiffWriter.buildOutputLines`, the per-line right-edge clip, the per-host
cursor-compensation walks, the diff, the writes. `buildOutputLines` is called
only from `RenderLoop`, and `ab_bench.py` never starts one.

That is not a small blind spot. It is where every terminal quirk workaround in
the framework lives, and a change there can be measured by `ab_bench.py` as
exactly zero while being worth 2% of a real app's CPU.

The one-command proof, worth re-running whenever this is doubted — force the
heaviest compensation walk of any host and compare it against the lightest:

```sh
TERM_PROGRAM=Apple_Terminal $BIN --bench --scenario dashboard --iterations 4000
TERM_PROGRAM=ghostty        $BIN --bench --scenario dashboard --iterations 4000
```

144.3 µs vs 143.7 µs — identical. If emission were in the timed region it
could not be.

`emit_bench.py` measures that half. It runs the app for real — a PTY,
`--autopilot`, the host forced by environment — and reads the process's own
CPU time over a fixed window, the technique `idle_cpu.py` already established
here (`ps -o cputime=`; `RUSAGE_CHILDREN` reads 0 for a live child). The
statistics are `ab_bench.py`'s, for the same reasons: CPU time not wall clock,
order randomised per rep, paired ratios, a bootstrap interval, and
"indistinguishable" whenever that interval touches 1.0.

```sh
Tools/Profiling/emit_bench.py /tmp/old /tmp/new --host Apple_Terminal
Tools/Profiling/emit_bench.py /tmp/old /tmp/new --scenarios dashboard --window 8.0
```

**Its resolution is coarser than `ab_bench.py`'s**, and the reason is `ps`:
CPU time comes back in centiseconds, so a scenario burning 0.25 s over the
window has two significant digits and ties are common. Lengthen `--window`
before believing a small number — the same measurement went from ±5.2% at
`--window 3.0` to ±3.5% at 8.0. A tie is reported as indistinguishable, not
as a verdict.

## The pieces

### `record.sh` — orchestrator
Builds `Example` in release with `-g`, drives the chosen scenario
under the Time Profiler, then analyzes the trace.
`record.sh [scenario] [seconds] [rows] [cols]`.

### `drive.py` — PTY driver
Launches a binary inside a pseudo-terminal (so raw mode + `TIOCGWINSZ`
work), feeds it scripted keyboard/mouse input, and drains output so the
child never stalls. Scenarios: `tour`, `list`, `table`, `emoji`,
`scroll`, `mouse`, `idle`, `progress`.

```bash
# Drive without profiling — a fast sanity check that the app responds:
.build/release/Example        # don't run this directly; use:
swift build -c release --product Example
python3 Tools/Profiling/drive.py \
    "$(swift build -c release --product Example --show-bin-path)/Example" \
    --scenario mouse
```

Keyboard input is raw terminal bytes (arrows = `ESC[A/B/C/D`, page jumps
= the `ContentView` shortcut chars). Mouse input is SGR 1006 reports
(`ESC[<button;col;row;M/m`). It returns to the main menu with two
Escapes — one may only close a combo field's suggestions — and quits the app
with `q` from there; an app that does not quit is reported as an error (exit
2), since the scenario's keys went somewhere it did not mean them to.

The app runs with `TUI_CONFIG_DIR` set to a fresh temporary directory,
deleted when the run ends, so a profile neither reads nor writes your own
settings and every run starts from the defaults. Set `TUI_CONFIG_DIR`
yourself to profile against a particular saved state; that directory is used
as given and kept. `python3 Tools/Profiling/test_drive.py` checks both.

`--dump OUT.ansi` writes the app's output exactly as it arrived, and beside it
`OUT.ansi.steps.json`: the scenario, the size, and one marker per scripted
step — its index, the input sent (`ESC[B`, `-`, or empty for a pause), and
the dump `offset` at the moment it was sent. Startup is marker 0, at offset 0.
The bytes from one marker to the next are what the app wrote in answer to that
step, as near as a PTY can say: a slow frame can spill past the next marker,
since nothing in the stream says where a frame ends. The markers live in a
sidecar, not in the stream, so every byte count taken from the dump is still
the app's own. `test_drive.py` checks that the stream is unchanged, that no
marker falls after its own step's reply, and that most fall after
the previous step's.

### `analyze_timeprofile.py` — trace → hot functions

> **`--blame` is usually the one you want.** Self time says where the CPU was,
> and for this framework the honest answer is `swift_release`, `swift_retain`
> and `malloc` — true, and useless, because none of them is a thing anyone can
> go and fix. `--blame` credits each sample to the nearest TUI frame
> *beneath* the leaf, turning "the runtime is busy" into "this function is
> making it busy". With a regex it restricts to samples that bottomed out in a
> particular kind of work:
>
> ```sh
> python3 Tools/Profiling/analyze_timeprofile.py t.trace --blame
> python3 Tools/Profiling/analyze_timeprofile.py t.trace \
>     --blame 'swift_retain|swift_release|_malloc|tiny_|Metadata'
> ```
>
> On the `menu` tree the leaf view said 55% libswiftCore and named nothing
> actionable; `--blame` said environment access 15.8%, `AnyIterator.next()`
> 9.2%, identity nodes 3.8%, string building 3.3% and array regrowth 3.0%.
> Those shares were taken before 2026-10-08, so they count each distinct stack
> once; see "Shares quoted before 2026-10-08" below.

**`--within PATTERN`** is the other way round: it keeps only the samples with
a frame matching PATTERN (a regex) somewhere on the stack, and ranks what
THEY spent their time on — what one function's inclusive time is made of,
leaves and all. Percentages stay shares of the whole profile, so the same
command over a before and an after trace compares directly:

```sh
python3 Tools/Profiling/analyze_timeprofile.py t.trace --within 'viewValueHash' --top 30
```

On the value hash's wiring (`fanout`, 2026-09-29) it said that 238 ms of the
hash's 422 — more than half — was the main actor's executor check
(`swift_task_isCurrentExecutor`, `Actor.unownedExecutor`, `MainActor.shared`,
the metadata accessors under them), which the inclusive view spreads across
every closure the hash passes to `withUnsafeBytes`, and no leaf ranking puts
together. Those milliseconds were taken before 2026-10-08, so they count each
distinct stack once; see "Shares quoted before 2026-10-08" below.

**Profiling the live app, emission included.** Instruments cannot `--launch`
a PTY app and `--attach` is denied here, but `xcrun xctrace record
--all-processes --time-limit 8s` records everything on the machine while
`idle_cpu.py` drives the app under autopilot; `--process <name>` then keeps
only that process's samples. That is the only profile that shows the output
half of a frame (`FrameDiffWriter`, the cell diff, `SGRState`), which
`--bench` never runs. The recording is large and Instruments leaves an
`instruments*.ktrace` of 100–900 MB in `$TMPDIR` after EVERY recording —
delete both once analysed.
Exports the trace's `time-profile` table via `xctrace export` and
aggregates CPU time into five views:

- **Self time** — leaf frame of each sample (where the CPU actually was)
- **Inclusive time** — every distinct function on a sample's stack
- **By module** — your code vs. system libraries
- **App only (self / inclusive)** — restricted to TUI / Example

```bash
python3 Tools/Profiling/analyze_timeprofile.py profiling-traces/emoji-….trace
python3 Tools/Profiling/analyze_timeprofile.py TRACE --thread main --top 40
python3 Tools/Profiling/analyze_timeprofile.py TRACE --state all   # include off-CPU
python3 Tools/Profiling/analyze_timeprofile.py TRACE --process Stress  # one process of an --all-processes trace
```

**What a percentage is a share of:** every sample the filters keep
(`--state`, `--thread`, `--process`), each with its weight, which is 1 ms per
sample in a Time Profiler recording. The header gives the counts. `rows=` is
every sample in the export, and `counted=` is the ones the filters kept; under
`--state all` with no other filter the two are equal. `--within` keeps that
denominator and narrows only the numerators. So the header, threads
included, still counts every sample the filters kept, and the `within` line
says how many of them had a matching frame.

**Why a custom parser instead of DuckDB?** Instruments' XML writes anything it
has written before as a reference, at two levels. For a frame, the first
occurrence is `<frame id="11" name="swift_release">` and every repeat is
`<frame ref="11"/>`, with no name. For a whole stack, the first sample with it
carries `<backtrace id="10">` and its frames, and every later sample with the
same stack carries only `<backtrace ref="10"/>`, with no frames at all. A tool
that misses either kind (the common DuckDB exporter misses frame refs)
**undercounts exactly what repeats, which is the hottest work**. This parser
resolves every ref it reads (a sample's weight, thread, process, state and
stack, and the stack's frames and binaries), so each sample counts once with
its weight, and it reports on stderr any of those refs it cannot resolve. The
export's refs for a sample's core, a binary's path and a process nested in a
thread feed no number, so it does not read them. A sample xctrace recorded
with no stack (`<sentinel/>`; 2 rows of about 300,000 in twelve traces) is
counted as `<no backtrace>`, which stands for both its function and its
module. It is a placeholder, so no `--within`, `--blame` or `--callers`
pattern matches it.

> **Shares quoted before 2026-10-08 count each distinct stack once.** Until
> then this parser resolved frame refs but not backtrace refs. A repeated
> stack came out empty and was skipped, so it kept only each stack's first
> sample: 21–64% of the samples in that day's traces, with the hottest stacks
> under-weighted most. In one trace of Stress's `app-shapes`, the app's own
> sort was 19.1% inclusive before the fix and 75.2% after. The percentages in
> earlier commit messages, and this README's examples, were computed that way.
> Treat them as indicative; a full count may rank them differently.

### `idle_cpu.py` — idle-cost probe
Launches the app in a PTY, waits a settle period (optionally sending keys
to reach another screen first), then measures CPU time and render output
bytes over a no-input window. A static screen must approach 0% CPU and
0 bytes/s; an animating one (spinner, focused pulse, text cursor) is
non-zero continuously. This is the probe behind the demand-driven
animation-clocks work.

```bash
python3 Tools/Profiling/idle_cpu.py BIN [settle_s] [window_s] [keys]
python3 Tools/Profiling/idle_cpu.py BIN 3 10 --page spinners --wakeups
```

`--page NAME` launches the binary with `--page NAME` (the Example lands on that
`DemoPage` case without navigating); positional `keys` still drive there by
keystroke instead. The child always runs with `TUI_CONFIG_DIR` pointed at a
fresh temporary directory, removed afterwards, so a probe never touches the
user's settings.

Three numbers per window, plus one on request:

| | |
|---|---|
| **CPU %** | `ps -o cputime=` before and after (`RUSAGE_CHILDREN` reads 0 for a live child). Centisecond resolution: lengthen the window before believing a small one. |
| **bytes/s** | Render output drained from the PTY. |
| **bursts/s** | Reads that arrive more than 5 ms after the previous one — roughly one per frame or replayed tick that wrote something. A wake that wrote nothing is invisible to it. |
| **idle wakeups/s** (`--wakeups`) | `top -l N -s 1 -pid PID -stats pid,cpu,idlew` sampled across the window. IDLEW is cumulative, so the reading is the difference between the first and last sample, per second — never a single row. Counts every exit from idle, whether or not it drew. macOS only. |

For an A/B, alternate the two binaries run by run (five each is the minimum
worth reporting) on a machine whose load average is below about 1.5, with
nothing building, testing or benchmarking, and report the median and spread of
each column. A single run of an animated page moves by several percent.

## How fast an animation really steps — `animation_rate.py`

`idle_cpu.py` says what an animated page costs; this says whether it is running
at the rate it asked for, which the cost cannot tell you (a clock that runs slow
makes a page look cheaper). It decodes the child's output with `pyte`, times
every change of every cell's character, groups adjacent animating cells into one
animation, and prints each one's median change interval beside its nominal
`SpinnerStyle.interval` — parsed from `Spinner.swift`, so the table cannot
drift — and the ratio.

```bash
python3 Tools/Profiling/animation_rate.py BIN 12                 # the Spinners page
python3 Tools/Profiling/animation_rate.py BIN 12 --page progress  # medians only
```

A ratio near 1.00 on every style is the goal. The same ratio well above 1 on
every style at once means the animation clock loses time, not that any one
spinner asks for the wrong duration. Only character changes are seen, so a
colour-only animation (a breathing focus ring) is invisible, and needs `pyte`
like `page_open.py`. **pyte abandons a write at a U+FE0F** (VS-16): a row with
an emoji-presentation cluster reads truncated whatever the app sent — use
`Tools/Smoke/raw_probe.py` for those.

### `analyze_stream.py` — where the BYTES went
Attributes the output a run produced, rather than the time it took. Give it a
stream captured by `drive.py --dump OUT.ansi` and it splits it into the three
things a stream can be — styling (SGR), positioning and erasing (other CSI),
and the cells themselves — then replays it through a minimal terminal model to
say how much of the styling was *necessary*. That last part is the point: a
frame can be correct, fast to produce, and still spend most of itself
restating a colour the terminal already had.

```bash
python3 Tools/Profiling/drive.py BIN --dump /tmp/frames.ansi
python3 Tools/Profiling/analyze_stream.py /tmp/frames.ansi
```

Two estimates price output changes before anybody builds them
(`Documentation/Terminals/Ghostty VT reference adoption study.md`, O2 and O3):

- **`--runs`** counts, against today's stream, what each of O3's four byte
  trims would save on its own: the padding a whole-line row writes after its
  `ESC[2K` (the erase already painted those cells — counted only where a
  trailing blank shows nothing but the background in force at the erase, so
  a reversed or differently coloured run to the row's end, such as a selected
  row's highlight, is not padding), blank runs of five or more
  at a span's end that `CSI n X` could erase (only where the blanks carry
  nothing an erase would lose, such as an underline), absolute moves to a later
  column of the row the cursor is on that `CSI n C` could replace, and the `;1`
  of a column-1 `CSI r;1 H`. The four overlap — a move counted under CUF may
  also be a column-1 move — so they are not added up.
- **`--shift`** is O2's hardware-scroll estimate. It replays the stream
  through `pyte`, step by step from the markers file, and asks of each step
  whether a band of at least four rows moved by k whole rows (|k| up to half
  the height). Where one did, it counts the bytes the step spent on the band,
  less what painting the rows a scroll exposes would cost and the ~20 bytes of
  `CSI a;b r`, `CSI k S` and `CSI r`. It prints the total, the share, the
  shifts used, and the three steps that pay most, by marker index, to check
  by eye. An upper bound on the saving: it knows nothing of O2's exclusions
  (compensated clusters, images, replayed animation rows). And pyte abandons a
  write at a U+FE0F (above), so on a page with emoji the model is wrong from
  that point; prefer the text-heavy scenarios.

`python3 Tools/Profiling/test_analyze_stream.py` checks both against streams
small enough to count by hand.

`--shift` reports two searches. **Exact bands** are rows equal to their
source k rows away, as O2 is specified. **With an N-cell residue** (`--residue
N`, default 4) a row also rides the shift when it differs from its source in
at most N cells, which are then repainted after it: a scroll view's own
indicator column (the arrows and the thumb sit still while the rows move under
them) cuts every exact band, and the residue is what O2's step 4 says the
ordinary diff writes. Only shifts that moved at least one row exactly are
tried.

The capture O2 and O3 wait on (M0 in the adoption study). Bytes, not time, but
a loaded machine coalesces keys into fewer frames and so writes fewer bytes, so
take the numbers that go in a commit message from a quiet box. Pass
**`--answer-fence`**: without it the PTY answers none of the app's startup
exchanges, each waits out its half-second deadline, and the first frame comes
about 1.5 s after launch — so a scenario's keys land during startup and are
parsed as one burst once the app is up. Measured 2026-10-05 on a debug
Example, `scroll` drew its page for the first time at step 83 of 93 without
the flag. It is off by default so a number taken before it existed stays
comparable; one taken since the startup exchanges existed may share that
artefact, and which do is not established.

```bash
BIN="$(swift build -c release --product Example --show-bin-path)/Example"
mkdir -p /tmp/m0
for scenario in tour splitdrag table scroll list; do
    python3 Tools/Profiling/drive.py "$BIN" --scenario "$scenario" --answer-fence \
        --dump "/tmp/m0/$scenario.ansi" --quiet
done
python3 Tools/Profiling/analyze_stream.py --runs --shift /tmp/m0/*.ansi
```

The study's thresholds: a trim is kept only where its scenario shows at least
3%, and the hardware scroll is built only if `scroll` and `list` show at least
50% fewer bytes.

**Read the scenarios before the numbers (2026-10-05).** None of the five
scrolls a full-width band. `scroll`'s views are bordered boxes seven rows tall
with their own indicator column; `table`'s file browser shows five rows; and
`list` scrolls nothing at all, because the Lists page now opens with the focus
in a search field and its Down keys move nothing (the bytes after its first
frame are a blinking caret). So a 0% from `--shift` on these says the
scenarios cannot answer O2, not that O2 saves nothing; only a page with a
tall, full-width list can.

### `idle-image.sh` + `IdleProbe` — idle cost with nothing else awake
`idle_cpu.py` answers "what does a static screen cost?" only for a screen that
is genuinely static, and every `Example` page carrying an `Image` also carries
focusable controls — a focused control pulses, so the loop is legitimately
awake and the reading says nothing about the image. `IdleProbe` is a minimal
app whose whole scene is the thing under test and nothing else;
`idle-image.sh` builds and runs it for the `Image` case.

```bash
Tools/Profiling/idle-image.sh
```

Reach for this shape whenever the question is "does X keep the loop awake?"
and X shares a page with anything else that legitimately does.

## Interpreting a run

A driven `tour` trace typically shows (on this hardware):

- ~99% of CPU on the **Main Thread** — the render loop is single-threaded.
- Inclusive: `AppRunner.run` → `RenderLoop.renderScene` → `renderToBuffer`
  (~85%), with `measureChild` / `ChildView.measure` (the two-pass layout
  **measure** pass) a large fraction of that.
- Self time dominated by **Unicode width measurement**
  (`_swift_stdlib_getBinaryProperties`, `Character.terminalWidth`) and
  **String/UTF-8 scalar-index** work — both prime caching / algorithmic
  targets.

Capture both a **driven** trace (page switches + scrolling: layout +
diff heavy) and an **idle** trace (`idle` scenario: steady-state per-frame
cost) — they stress different paths.

## Recording results

Profiling that motivates a change is recorded **in the commit message**,
not as committed files — raw `.trace` bundles are large and git-ignored.
A profiling-driven commit quotes the relevant `analyze_timeprofile.py`
excerpts (the hot functions / percentages that matter) and explains how
they informed the change (what was hot, why the change addresses it,
before/after when available). See the "Performance & profiling" rule in
[`.claude/CLAUDE.md`](../../.claude/CLAUDE.md).

## Mode A — headless render harness (`RenderHarness`)

`RenderHarness` is an executable target (`Tools/Profiling/RenderHarness`)
that builds a representative view tree and calls
`renderToBuffer(view, context:)` in a counted loop, then exits. Each tree
keeps its concrete `View` type (no `AnyView` erasure) so the profile
reflects the real `measureChild` / `Layoutable` dispatch.

Trees (`--tree`): `alignment` (three flexible bordered boxes — heavy on the
measure pass), `nested` (a Panel column beside that row), `frames` (bare
`.frame`s where each `FlexibleFrameView` is itself the measured child),
`paneled` (a Panel and a Card wrapping multi-line content — the
labeled-container measure path), `memoRows` (a column of `.equatable()`
bordered rows — the value-based measure memo), `stackRows` (plain
`ForEach` rows in a `VStack` — the automatic `Equatable`-element row
memo), `list` (a long `List` of `ForEach` rows — the lazy visible-window
row rendering), and `form` (a settings page of interactive controls).
Seeds: the shapes in `Benchmarks/TUIBenchmarks/RenderBenchmarks.swift`
and the layout tests.

```bash
swift build -c release --product RenderHarness -Xswiftc -g
BIN="$(swift build -c release --product RenderHarness --show-bin-path)/RenderHarness"
xcrun xctrace record --template "Time Profiler" --output harness.trace \
    --launch -- "$BIN" --tree alignment --iterations 10000
python3 Tools/Profiling/analyze_timeprofile.py harness.trace
```

The harness installs what `RenderLoop` installs — state storage, a render
cache, a preference store, a **volatile read tracker** (a precondition of the
measure memo, not a diagnostic), an identity tree rooted at a TYPE — and runs
the per-pass lifecycle around every iteration. That is fidelity, not ceremony:
without the prune this harness reported `list` at 108 MB of peak RSS and
`memoRows` at 23 MB, against 8.3 MB and 7.9 MB once the pass closes properly.
A harness that never prunes is measuring itself.

This gives deterministic, input-timing-free profiles ideal for
before/after comparisons while optimizing. Because the harness exits
quickly and takes no input, a plain `/usr/bin/time -p "$BIN" --tree …` is
also a reliable, low-overhead before/after signal where Instruments
sampling is impractical (e.g. a VM where the Time Profiler runs slowly).

Build it with `--product RenderHarness` (or set `BENCHMARK_DISABLE_JEMALLOC=1`)
so the build does not pull the `jemalloc`-backed benchmark target.

Future trees worth adding: a `Table`, a `ScrollView` mid-scroll.

## Mode A, for pictures — `ImageHarness`

`RenderHarness` loops a view render; `ImageHarness`
(`Tools/Profiling/ImageHarness`) loops an `ASCIIConverter` over a picture. It
needs a target of its own because the image pipeline has **two halves with
costs two orders of magnitude apart**, and a change to one of them says nothing
about the other:

| `--path` | what it runs | asked | reported as |
|---|---|---|---|
| `glyph` | `convert` — an SGR per cell | ~2 per CELL | ns/cell |
| `pixel` | `recoloured` — the picture a graphics protocol carries | once per PIXEL | ns/pixel |
| `colour` | `Color.downsampledToPalette256()` alone, over distinct colours | — | ns/colour |

A cell is about 8×17 device pixels, so the same picture asks the pixel path
roughly two hundred times more often than the glyph path. That is why an exact
palette search is affordable per cell and ruinous per pixel, and why a table
lookup can be the right trade in one and pointless in the other.

`--path colour` exists because in both of the others the quantiser is a small
part of a large total — resampling, sharpening, glyph choice and string
building are most of what a conversion costs — so a quantiser that got four
times dearer can hide inside `--path glyph`'s noise and still be the wrong
trade. It uses distinct colours deliberately: `Color`'s answer is memoised, and
a loop over one colour measures a dictionary.

```bash
swift build -c release --product ImageHarness
BIN="$(swift build -c release --product ImageHarness --show-bin-path)/ImageHarness"
"$BIN" --path glyph --mode ansi256 --iterations 30
"$BIN" --path pixel --mode ansi256 --dither floyd --iterations 8
"$BIN" --path colour --cols 400 --rows 100 --iterations 3
```

Modes (`--mode`): `truecolor`, `ansi256`, `ansi16`, `grayscale`, `mono`,
`shades8`. The source picture is synthetic but has a photograph's colour
*statistics* — smooth gradients with enough grain that the colours are nearly
all distinct — because a picture of flat bands is answered by any memo and
would measure the memo instead of the quantiser.

`--edge-contrast <amount>` switches on the unsharp mask
(`ASCIIConverter.edgeContrast`), and it is the only way to measure that stage
at all. It is off everywhere by default — the environment value defaults to 0
and the Example page's toggle starts off — so without the flag
`RGBAImage.sharpened` never runs; and `Stress` has no image scenario, so
`ab_bench.py` and `emit_bench.py` never reach the image pipeline in the first
place. Measure it on `--path pixel`, where the mask runs at radii 1×1 over the
whole pixel grid (816,000 px at 120×50); on `--path glyph` it runs over the
box-reduced sub-cell grid instead — 120×100 for the default charset, sixty-odd
times smaller — so a glyph-path number says almost nothing about it.

One trap in reading the checksum: switching the flag on CHANGES it, because the
mask moves the middle pixel it samples. So a checksum that is equal with and
without `--edge-contrast` is proof the mask never ran, and a checksum that
differs between those two runs is the cheapest positive confirmation that it
did. Only compare checksums between two BUILDS at the same flag setting.

Each run prints a checksum derived from the output, both to defeat dead-code
elimination and so two builds that should agree can be seen to.

For an A/B, build both binaries, keep a copy of each, and alternate them —
`ab_bench.py`'s statistics do not apply here (this harness reports wall time
for one binary, not paired CPU-time ratios), so run three or more alternating
reps and look at the spread before believing a small difference.
