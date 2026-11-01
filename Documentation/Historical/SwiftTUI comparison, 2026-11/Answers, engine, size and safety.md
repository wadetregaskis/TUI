# TUI versus SwiftTUI: engines, size, tests, safety

Written 2026-11-01 for TUI's owner. Both frameworks were built and run. Nothing in the TUI repo was edited.

**Versions.** TUI `main` at `3d605c2c4`, in a clone. SwiftTUI `207913d23`, just after 0.20.0, with swift-collections 1.7.5. Swift 6.4.0 from swiftly, release, on one Mac: macOS 15.8.1, arm64, a VM, 14 cores, 32 GB.

**Marks.** [M] measured here. [V] read in source. [S] stated by the project. [I] my inference.

**Paths.** Tools, the benchmark programs and a compact baseline of these results are in `Tools/SwiftTUIComparison`. Paths like `results/`, `gen/` and `q16/` below are relative to where this run kept them, and raw samples and logs weren't kept.

**How to read the numbers.**
- The machine was shared with up to 4 other lanes. One-minute load was mostly 4 to 8, peaking near 40. Each result row states its load in `results/*.jsonl`.
- **Timings are rough.** Most rows are 3 process runs of 40 presses: the figure is the median of the runs' medians, then [lowest to highest run].
- **Instruction counts were not available.** `proc_pid_rusage` returns 0 for them on this VM [M]. So the deterministic measures are bytes written and **allocation counts**, from a small interposer I wrote (`alloc/alloccount.c`). They repeat to about 0.1% across runs. CPU time comes from rusage. The interposer did not move timings: with and without it, 115 to 123 ms against 116 to 118 ms for SwiftTUI, and 1.6 to 1.7 ms either way for TUI [M, 2 runs of 20].
- **The driver** (`scripts/driver.py`) is a PTY of 200 × 50 that answers terminal queries as Ghostty would. Key latency is from writing the key to the marker's bytes reaching the driver. So it includes the kernel and my Python, a few hundred µs [I].
- **Same source.** The benchmark views are one file (`gen/bench_common.swift`), compiled unchanged against both, except `Table`, whose API differs. SwiftTUI's browser companion was off unless stated, which helps it.

---

## Q14. Rendering engines

### The short answer

**On most of what I measured TUI is much faster, roughly 5 to 100 times per interaction, and uses far less memory.** the first report argued that a retained graph, dependency tracking and an off-main tail "should scale better for small updates to big trees". In this implementation they do not: a SwiftTUI frame costs work in proportion to the whole tree even when one leaf changed.

**SwiftTUI wins clearly in four places:**
1. **Slow bodies that did not need to run:** 8 to 30 times, because it does not run them, while TUI runs them twice a frame. This is a real TUI weakness, and I would put it first.
2. **Blended compositing of 30 layers:** about 2.5 times TUI's frame rate.
3. **Output bytes while scrolling:** up to 35 times fewer.
4. **Idle with a focused control:** TUI's focus pulse keeps painting.

### What each claimed capability actually does

| Claimed capability | Present? [V] | What I measured it doing | TUI today | What TUI would need |
|---|---|---|---|---|
| **Retained view graph; re-evaluate only the dirty part** | Yes: `ViewGraph`, dirty frontier planner | Works for bodies: resolve is about 6.5% of a leaf frame, and slow siblings are not run (8 to 30× TUI). But the other work per frame stays proportional to the whole tree: the retained index, checkpoints, the semantic tree, the animation walk | **Partly.** A walk from the root, with memos cutting off `.equatable()` views and `ForEach` rows. Elsewhere every body runs each frame, twice | A memo on plain composite views: same type, equal stored inputs, no reads that changed, and one evaluation per frame instead of two. Your `ValueHash` plans and Option C are most of the machinery [I]. M to L. No retained graph needed |
| **Dependency tracking** | Yes: per-node read certificates | `tree-obs` and `tree-leaf` cost the same as each other in both frameworks | Yes: `withObservationTracking`, scoped invalidation | Nothing |
| **Off-main frame tail** | Yes: `SWIFTTUI_RENDER_MODE` switches it, so I A/B tested on one binary | **Helps only when the tail is the cost:** 979 against 1,566 ms on the blend case. No help on `lat-heavy`. **Worse** on `lat-slowbody`: 178 against 124 ms | No. One thread walks and draws | XL as a port: body evaluation and drawing are one walk, and the services are main-thread objects. A much smaller step would take the pure compositing to a worker, or simply make that path faster (see below) |
| **Frame cancellation** | Yes | Cancels queued tails: 7 of 31 and 23 of 46 frames. On `lat-heavy`, turning it off (`async-no-cancel`) halved latency, 648 against 1,356 ms (one run, 10 presses, treat as indicative). So it may be costing rather than helping there | Pacer coalesces: all pending input folds into the next frame | Nothing |
| **Completed-frame dropping** | Yes | **0 frames dropped** in 12 traced runs, 8 of them under real load. The trace says `blocked` or `commit_ordered` for every one, with blockers like `handlerInstallations` [M] | No | Nothing: I saw no benefit to chase |
| **Iterative layout on heap stacks** | Yes for measure and place | **Did not make deep trees safe.** It crashes near depth 200 by default; TUI's recursive walk ran 1,000 and then truncated without crashing | Recursion plus `StackGuard` | Nothing urgent |
| **Scroll-region output (`CSI r`, `CSI S`)** | Yes, `1;50r` then `1S` | Real: 132 bytes a notch on similar rows, sent as one synchronized frame. See table (b) for dissimilar rows | No. `CSI r` only at setup and exit | About M. Find a shift by comparing old and new line hashes in `FrameDiffWriter`, emit it inside `?2026`, and only for full-width bands. The survey must cover it per terminal: images, tmux, Terminal.app. The survey notes "no frame scrolls today" at line 7172 |
| **Semantic tree each frame** | Yes: accessibility, reader, hosts | Part of the bill: 25% of the worker's samples in a leaf frame (`SemanticExtractor`), 6% on main for `TerminalReaderModel.update` | No | L; TUI should make it conditional on being asked for, not per frame |
| **Non-terminal hosts** | Yes | Not measured | No | XL |

### (a) One leaf changes in a large tree

A 48 × 40 grid of `Cell` views (1,920 `Text`) fills the screen. One key press changes one thing. Bytes is the frame that carried the marker. SwiftTUI's press commits 2 frames (pressed, released), so its per-frame cost is about half of the CPU and allocation columns; its latency is one frame [M: frame trace].

| Scenario | Framework | Key to marker, ms: median of runs [range] | p95 ms | Bytes | Allocations | CPU ms | First frame |
|---|---|---:|---:|---:|---:|---:|---:|
| Leaf's own `@State` | **TUI** | **1.98** [1.63 to 2.45] | 3.08 | 40 | 642 | 3.2 | 0.10 s |
| | SwiftTUI | 120 [115 to 123] | 128 | 209 | 469,700 | 238 | 1.03 s |
| `@Observable` read by the leaf | **TUI** | **1.34** [1.30 to 1.73] | 1.87 | 40 | 804 | 1.7 | 0.11 s |
| | SwiftTUI | 118 [116 to 126] | 124 | 209 | 469,000 | 236 | 1.07 s |
| `@State` at the root, read by one leaf | **TUI** | **20.6** [19.8 to 21.4] | 25.5 | 40 | 46,300 | 21 | 0.11 s |
| | SwiftTUI | 341 [335 to 362] | 381 | 209 | 1,200,000 | 461 | 1.16 s |
| Every cell changes | **TUI** | **21.9** [21.9 to 23.3] | 23.7 | 10,900 | 56,000 | 23 | 0.09 s |
| | SwiftTUI | 513 [511 to 763] | 545 | 12,900 | 1,400,000 | 635 | 1.09 s |

3 runs of 40 presses each.

**How it scales.** Same scenario, 2 runs of 20, range of the 2 medians:

| Cells | TUI leaf, ms | SwiftTUI leaf, ms | TUI root, ms | SwiftTUI root, ms | Allocations TUI / SwiftTUI, leaf |
|---:|---:|---:|---:|---:|---:|
| 40 | 0.69 to 0.80 | 7.0 to 8.8 | 1.1 to 1.4 | 12 to 14 | 505 / 23,700 |
| 200 | 0.75 to 1.18 | 16 to 19 | 2.7 to 3.2 | 36 to 42 | 572 / 62,700 |
| 960 | 1.08 to 1.49 | 58 to 66 | 9.8 to 11.6 | 162 to 166 | 608 / 241,600 |
| 1,920 | 1.52 to 2.08 | 116 to 129 | 19.8 to 21.7 | 327 to 349 | 690 / 469,700 |

**What this means.**
- **In this grid, TUI's leaf change is nearly flat with tree size, and SwiftTUI's grows in proportion to it.** At 40 cells, a small realistic page, SwiftTUI is at 7 to 9 ms a frame and perfectly usable. At 1,920 cells it cannot sustain 10 fps.
- This reverses the first report's expectation, with a caveat: **the grid is built with `ForEach`, and TUI's flat line is its row memo.** "Retained's own case" below shows the other side.
- The reason for SwiftTUI's slope is in the profile.

**Where SwiftTUI's leaf frame goes** [M: `/usr/bin/sample` over 233 presses, `results/sample-st-tree-leaf.txt`; shares of samples per thread, inclusive]:

| Thread | Work | Share |
|---|---|---:|
| Main | Frame acquisition total | 51% |
| Main | `commitCompletedFrameCandidate` | 24% |
| Main | `RetainedFrameIndex` patch | 12% |
| Main | `computeFrameHead`: **resolve, the actual body work** | **6.5%** |
| Main | `TerminalReaderModel.update` | 6% |
| Main | `ViewNode.Checkpoint` copies and restores | 8 to 15% |
| Worker | Tail total | 35% |
| Worker | `SemanticExtractor.extract` | 26% |
| Worker | Layout | 10% |

Top self time is `swift_release`, `memmove` and `swift_retain`: copying large trees of values. So the retained graph does its job, and it avoids evaluating bodies. Everything around it then walks or copies the whole tree. Immutable phase products, retained for the next frame's diff and for the checkpoint a cancelled frame would restore, cost that.

**TUI's cost in the root case (46,300 allocations)** is your known "memos die on an ancestor write". It is still 16 times SwiftTUI's in time.

#### Retained's own case

A leaf with state beside two siblings whose `body` takes 50 ms and whose inputs never change. This is the case a retained graph exists for. I added it because everything above is flattering to TUI. `lat` is key to marker; 3 runs of 10, under load 16 to 69, so the SwiftTUI figure is inflated (6 to 7 ms in one quiet run of 6).

| Scenario | TUI | SwiftTUI |
|---|---:|---:|
| State in the leaf, slow siblings | 216 ms [201 to 228] | **28 ms** [24 to 29] |
| State in the parent, slow siblings | 208 ms [201 to 215] | **26 ms** [17 to 27] |

**Here SwiftTUI wins by 8 to 30 times.** The 200 ms is 2 siblings × 50 ms × 2: TUI runs a plain sibling's `body` again on every frame, and twice (measure, then render) [I, from the arithmetic and `RenderCycle.md`]. Memos cover `.equatable()` views and `ForEach` rows, and these are neither. SwiftUI would not re-run those bodies [I: its documented behaviour; I did not probe it]. So a SwiftUI author who sorts an array in `body` pays nothing there, and pays each frame here. The focus pulse does not re-run them: idle CPU stays low [M].

Then the same question for many cheap bodies. **A static tree with no `ForEach`** (4^d leaves, composite `Fan` views; `fan-leaf`, 3 runs of 15, load about 40):

| Leaves | TUI, ms | SwiftTUI, ms | Allocations TUI / SwiftTUI |
|---:|---:|---:|---:|
| 64 | 6.6 [4.4 to 8.4] | 30 [30 to 35] | 2,587 / 32,300 |
| 256 | 14.7 [13.1 to 15.2] | 61 [53 to 197] | 9,080 / 92,600 |
| 1,024 | 39.7 [36.7 to 44.3] | 182 [163 to 253] | 43,800 / 336,100 |

**So TUI's flat line above is the `ForEach` row memo, not the engine.** On a static tree TUI's cost also grows with the tree, because the walk runs each body. It stays 4 to 5 times faster, because each body and each frame costs so much less, but it is the same shape as SwiftTUI's. That corrects my own first reading.

### (b) Long list and table

Press Down, row after row. TUI moves the focus row; SwiftTUI moves the selection. Both repaint one or two rows. `Text` rows, both written as `List(0..<N, id:, selection:)` and `Table(data, ...)`, in a `VStack` under a one-line header, with no stated height, as SwiftUI code normally reads. 3 runs of 40 presses.

| N = 10,000 | Key to frame, ms | p95 | Bytes | Allocations | Footprint settled | Peak footprint | First frame |
|---|---:|---:|---:|---:|---:|---:|---:|
| TUI `List(data)` | **1.26** [1.26 to 1.28] | 2.1 | 482 | 2,029 | 10.7 MB | 12.3 MB | 0.25 s [0.06 to 0.62] |
| SwiftTUI `List(data)` | 1,578 [1,536 to 1,736] | 1,626 | 645 | 2,700,000 | 556 MB | 2.9 GB | 4.2 s |
| TUI `List { ForEach }` | **1.49** [1.42 to 1.50] | 1.9 | 482 | 2,798 | 10.3 MB | 12.3 MB | 0.06 s |
| SwiftTUI `List { ForEach }` | 3,965 [3,888 to 4,657] | 4,051 | 645 | 3,900,000 | 400 MB | 645 MB | 9.2 s |
| TUI `Table` | **1.20** [1.13 to 1.20] | 1.9 | 481 | 2,225 | 10.5 MB | 12.2 MB | 0.07 s |
| SwiftTUI `Table` | 10,700 [10,100 to 11,400] | 12,200 | 2,162 | 19,900,000 | 3.0 GB | **25 GB** | 22 s |

**Scale** (2 runs of 10; range of medians, ms per key):

| Rows | TUI `List` | SwiftTUI `List` | TUI `Table` | SwiftTUI `Table` |
|---:|---:|---:|---:|---:|
| 100 | 1.2 to 2.0 | 39 to 41 | 1.1 to 1.9 | 102 to 136 |
| 1,000 | 1.2 to 1.9 | 157 to 304 | 1.1 to 1.5 | 1,005 to 1,114 |
| 10,000 | 1.2 | 1,556 to 1,681 | 1.2 to 1.7 | killed by my 8 GB guard; the table above predates the guard |
| 100,000 | 1.1 to 2.1 | not run | 1.1 to 1.4 | not run |

**What this means.** TUI's cost is flat in N, and SwiftTUI's is linear, about 0.15 ms a row (`List`) and 1 ms a row (`Table`) per key. The sample of a 1,000-row list shows the layout stage on the main thread inside `measureWindowedHostedCollection`, calling `child(at:)` through `CustomLayoutHandle.measureChildren`, so rows get realized in the measure [M: `results/sample-st-list-data.txt`]. Their docs say a lazy source past a budget keeps the tail on the main actor (`Pipeline:349-351`), which matches. **A 25 GB peak on an ordinary-looking `Table` of 10,000 rows is a practical hazard: on a smaller machine it would be killed.**

**Fairness check: a stated height.** Their own table scenario sets `.frame(height: 26)`, and `Collections.md:157-161` says a collection with unbounded height "realizes every row", under `.fixedSize()` or an ideal-height probe, reporting `collection.unboundedRealization` once [S]. A `VStack` asking for an ideal height is that probe [I]. So the numbers above are that documented case. It is a poor default for SwiftUI code, which normally does not state a height, and I discarded stderr so I did not see their report; but it is not a hidden bug. With `.frame(height: 44)` (3 runs of 15; load 36 to 69, so times are rough; allocations are not):

| N = 10,000, stated height | Key to frame, ms | Allocations | Footprint / peak | First frame |
|---|---:|---:|---:|---:|
| TUI `List` | 8.4 [1.6 to 13.6] | 1,861 | 9.9 / 11 MB | 0.30 s |
| SwiftTUI `List` | 51 [46 to 65] | 32,200 | 34 / 65 MB | 0.51 s |
| TUI `Table` | 5.9 [1.7 to 11.4] | 2,061 | 9.9 / 11 MB | 0.27 s |
| SwiftTUI `Table` | 110 [89 to 112] | 115,400 | 49 / 107 MB | 0.60 s |

Allocations do not change at N = 1,000 or 100,000 in either [M], so **with a stated height SwiftTUI is flat in N too**, and its windowing claim holds. It is then 17 to 56 times TUI's allocations, and roughly 10 times its time. At 100,000 rows its first frame is 1.3 s and 109 MB (TUI 0.33 s and 10 MB). What differs is only the unbounded case, where TUI stays flat and SwiftTUI realizes everything.

**A `ScrollView { LazyVStack }` wheel notch** (3 runs of 40):

Wheel notches 350 ms apart; 3 runs of 25; load 42 to 55. The bytes are net of idle output. **Rows moved differ: TUI moves 3 rows a notch, SwiftTUI 1.**

| Rows | Framework | First frame, bytes | All bytes, net | Scroll-region ops | First byte, ms | Allocations |
|---|---|---:|---:|---:|---:|---:|
| Similar (`Row 123 some text…`) | TUI | 674 | 749 | 0 | **7** | **5,500** |
| | SwiftTUI | **124** | **132** | 1 a notch | 177 | 375,600 |
| Dissimilar (190 random letters) | TUI | 10,100 | 10,200 | 0 | **11** | **5,600** |
| | SwiftTUI | **282** | **290** | 1 a notch | 151 | 379,200 |

**What this means.** The scroll region works: 35 times fewer bytes on dissimilar rows. On rows that look alike, TUI's cell diff already gets most of it, sending only the changed digits. Its benefit is on the wire, not in the app: SwiftTUI spends 13 to 25 times longer per notch to reach its first byte. On a local terminal 10 KB per notch is nothing. Over a slow ssh link at 30 notches a second it is about 2.4 Mbit/s, and that would be felt [I].

### (c) Input latency while busy

The test off-main work was built for. The app runs a 16 ms ticker. I press a key every 250 ms and time the marker. 3 runs of 30 presses. Mode names are SwiftTUI's own switch, so `async` against `sync` is its engine against itself.

| Scenario | Who is the cost | TUI | SwiftTUI `async` (default) | SwiftTUI `sync` |
|---|---|---:|---:|---:|
| `lat-slowbody`: one 50 ms body | Body, main-bound | **106 ms** [104 to 106]; 8.4 fps | 178 ms [123 to 179]; 4.7 fps | 124 ms [109 to 126]; 2.7 fps |
| `lat-heavy`: 1,920 cells all change | Body and tail | **29 ms** [28 to 52]; 24 fps; 57% CPU | 1,243 ms [1,031 to 1,298]; 1.4 fps; 101% CPU | 1,191 ms [1,117 to 1,312]; 1.9 fps; 101% CPU |
| `lat-blend`: 30 blended full-screen gradients, cheap bodies | **Tail** | 2,905 ms [2,856 to 3,504]; 0.64 fps | **979 ms** [979 to 1,154]; 1.6 fps | 1,566 ms [1,551 to 1,705]; 1.6 fps |

(fps is synchronized-output frames per second; CPU is share of one core. `async` frames below 2 rows are not wrapped, so its `lat-slowbody` count understates [V].)

**What this means.**
- **Off-main does what it says on the case made for it:** a third less latency on `lat-blend`. Frames per second are unchanged, so it is latency only.
- **It does not help when bodies matter**, and on `lat-slowbody` it looks worse, since it adds hops [I].
- **Bodies are main-actor in both.** So a slow `body` hurts both equally. TUI takes about 118 ms a frame with a 50 ms body, which suggests it ran the body twice per frame (measure and render) [I, from the frame interval].
- **`lat-blend` is SwiftTUI's clearest win in the whole report.** TUI's compositing is about 2.5× slower per frame, and its total latency 3×. That is a stress scene (30 full-screen layers), though not an unreasonable effect: their ripple demo does it. Their changelog shows dedicated work here (span walks, `CHANGELOG:745-749`). **TUI could probably close most of this by optimising the blend path, with no threading**, since it is the only frame type here where TUI is the slower one [I].

### (d) Deep nesting

`VStack` inside `VStack`, D levels, a leaf with state. `deep-plain` is a recursive struct; `deep` wraps each level in `AnyView`. 2 runs, first frame and key to frame.

| Depth | TUI plain, key ms | SwiftTUI plain, default | SwiftTUI plain, `sync` | TUI `AnyView` | SwiftTUI `AnyView`, default | SwiftTUI `AnyView`, `sync` |
|---:|---:|---|---|---:|---|---|
| 25 | 0.86 | 14 ms | | 0.88 | 32 ms | |
| 50 | 1.08 | 18 ms | | 1.14 | 85 ms | |
| 100 | 2.68 | 38 ms | | 1.71 | **crash** (SIGILL) | 320 ms, first frame 3.5 s |
| 180 | | 87 ms, first frame 1.7 s | | | | |
| 200 | 3.99 | **crash** (SIGILL) | 101 ms, first 1.9 s | 3.45 | | 1,400 ms, first 13 s |
| 400 | 9.81 | | 354 ms, first 7.5 s | 8.64 | | 7,170 ms, first 55 s |
| 800 | 25.1 | | 1,370 ms, first 30 s | **blank** | | |
| 1,000 | fine | | | | | |
| 1,200+ | **blank**, no crash, alive | | 1,600: SIGSEGV in 1 of 2, no frame in 60 s in the other | | | |

**What this means.**
- **Default SwiftTUI crashes at a depth TUI handles easily**, even though its layout really is iterative. The crash report's worker stack is 215 frames of the recursive `FrameTailRetainedInput.collectReusablePhaseSubtrees` [M: `.ips`]. I did not prove that is the cause. The signal is re-raised by their handler, so the report is indirect. Their docs state the worker has a 512 KiB stack and that value destruction still recurses (`Pipeline:166-188`), and there is a budget for engine re-entry, but no such guard caught this tree.
- **`sync` mode goes deeper and is quadratic**: first frame 1.9, 7.5, 30 s at 200, 400, 800.
- **TUI degrades better but not perfectly.** Past about 1,000 levels (600 with `AnyView`) it draws a blank page and stays alive, with no message I saw. `StackGuard` is doing what your note says. A runtime issue saying why the page is blank would be a cheap improvement.
- **Real apps rarely reach this.** A 100-level `AnyView` chain is unusual. A deep outline or a recursive view at 30 to 50 levels is not, and at that depth SwiftTUI costs 14 to 85 ms a key, against about 1 ms for TUI.

### (e) Animation of many cells

8 s of steady state; 3 runs. Frames are `?2026` blocks per second; a burst count agreed with it.

| Scenario | Framework | Frames/s | Bytes/s | CPU, share of a core | Allocations/s | Peak |
|---|---|---:|---:|---:|---:|---:|
| `anim-opacity`: `withAnimation` on the whole grid's opacity | **TUI** | **20** | 198 KB | **6%** | 46,000 | 24 MB |
| | SwiftTUI | 3.5 [3.4 to 3.8] | 62 KB | 102% | 865,000 | 191 MB |
| `anim-move`: `.offset` on 48 `Text` rows | **TUI** | **28.8** | 48 KB | **14%** | 132,000 | 14 MB |
| | SwiftTUI | 26.9 | 59 KB | 64% | 678,000 | 68 MB |
| `anim-tick`: a 16 ms ticker recolours 9,600 one-cell `Text` views | **TUI** | **6.6** | 1.2 MB | 80% | 1,600,000 | 75 MB |
| | SwiftTUI | 0.25, one frame in 4 s | 55 KB | 102% | 3,100,000 | 704 MB |

**What this means.** TUI's animator replays cell runs without re-rendering where it can (`anim-opacity` at 6% CPU). At 20 fps it does not reach 60 here. Note the frame-rate column is capped by each framework's pacing, so compare with CPU. On the worst case neither is smooth; TUI gives a usable 6.6 fps and SwiftTUI a slide show. Interesting extra: a 6-second trace shows `sync` mode gives 5 fps against 3.5 fps for `async` on `anim-opacity` [M]; off-main is costing frames.

### (f) Idle CPU

20 s after 4 s settling; 3 runs. Bytes were 0 in a 12 s check of both, for a page with nothing focused [M].

| Page | Framework | CPU, % of a core | Wakeups/s | Allocations/s | Bytes/s |
|---|---|---:|---:|---:|---:|
| `hello`, nothing focusable | **TUI** | **0.00** | 0.05 | 0 | 0 |
| | SwiftTUI | 0.96 [0.93 to 1.21] | 45 | 248 | 0 |
| `counter`, focused button | TUI | 1.75 [1.46 to 2.09] | 5.9 | 2,916 | 1,123 |
| | **SwiftTUI** | **0.96** [0.92 to 1.22] | 45 | 248 | 0 |
| | SwiftTUI, companion on (its default) | 1.09 | 55 | 247 | 0 |
| 1,920 cells, focused button | TUI | 1.57 | 5.5 | 2,916 | 2,259 |
| | **SwiftTUI** | **1.04** | 45 | 247 | 0 |

**What this means.**
- **SwiftTUI has a constant idle floor of about 1% and 45 wakeups a second**, whatever the page. The sample shows 3 threads in `SceneDiscoveryServer.run` (`poll` then `Task.sleep`); the source confirms a 20 ms accept loop (`SocketServer.swift:271-290`). That is the `attach` feature. Its reader does sleep properly. Small, but it is a battery matter on a laptop, and a flat rate of wakeups is what power tools flag.
- **TUI is truly silent until something focusable exists. Then the focus pulse costs 1.6 to 1.8%** and writes 1 to 2 KB/s to the terminal, forever. That is a ruled design choice (your "focus always breathes"), and `TUI_REDUCE_MOTION=1` does **not** stop it [M: same bytes], which may surprise. An idle TUI app with a focused control costs more CPU than SwiftTUI's and also makes the terminal repaint. **For an app left open all day this is the number I would look at.** A slower pulse, or stopping it after some seconds without input, would fix it, at the owner's call.

### (g) Peak memory

3 runs; first frame reached, settled. Footprint as the OS counts it. SwiftTUI companion off.

| Page | TUI footprint / peak | SwiftTUI footprint / peak | First frame TUI / SwiftTUI | Allocations to settle TUI / SwiftTUI |
|---|---:|---:|---:|---:|
| `hello` | 8.0 / 8.0 MB | 8.6 / 8.6 MB | 0.07 / 0.31 s | 8,786 / 11,500 |
| 1,920 cells | 20 / 20 MB | 154 / 179 MB | 0.12 / 1.05 s | 125,000 / 2,200,000 |
| `List` 10,000 (`ForEach`) | 10.5 / 10.5 MB | 387 / 622 MB | 0.08 / 9.6 s | 36,000 / 11,100,000 |
| `List` 100,000 | 10.5 / 10.5 MB | 1.9 / 1.9 GB, no frame in 120 s | 0.07 s / none | 36,000 / 57,300,000 |
| `Table` 10,000 | 10.5 / 10.5 MB | 3.0 / 3.7 GB | 0.08 / 22 s | 33,400 / 55,800,000 |

**What this means.** Hello is a tie, so neither has a large base. Everything beyond that grows much faster in SwiftTUI, as it holds several immutable trees per frame (resolved, measured, placed, draw, raster, checkpoints). the first report said a retained model "pays for that"; the memory is the bill.

### Conclusions

**Is SwiftTUI actually faster? Generally no.** On the measured cases it is slower, by about 5 to 10 times at small sizes and 100 or more at large, with the exceptions below. On a page of 50 to 300 views, with no expensive bodies, the difference is 1 ms against 7 to 20 ms a key: both feel fine.

**Where its design is really better.**
1. **Expensive bodies that do not depend on what changed.** A retained graph just does not run them: 8 to 30 times better, measured. This is the one place where the engine's central idea pays off directly, and TUI cannot match it today.
2. **Compositing many blended layers.** Measured, clear, and off-main helps a further third. TUI should treat this as a known weak path. I suspect its span work more than its threads [I].
3. **Scroll regions.** Measured. Fewer bytes; on a local terminal the benefit is small, on ssh or tmux it is real [I].
4. **Separation of phases and hosts.** Clean products, a semantic tree for accessibility every frame, and non-terminal hosts follow naturally. That is value I did not measure, and it is what the per-frame cost pays for.
5. **Idle with focus**, by not pulsing, which is a design choice rather than an engine property.

**Where its design is not better, in spite of appearances.**
1. **Retained graph, as a route to scale.** It saves bodies, then pays per-tree bookkeeping every frame. Unless that bookkeeping becomes proportional to damage, this does not scale better. Their own profile says resolve is no longer what costs.
2. **Off-main tail.** Latency gain in one regime; a loss in others; a permanent API cost in `Sendable` bounds. With frames at 2 ms, TUI has nothing to offload.
3. **Frame dropping.** I never saw one fire.
4. **Iterative layout.** The deep-tree failure happens anyway, one layer away.

**Where TUI's is better.**
1. Work per frame. Nearly flat for `ForEach` rows and lists at any N, stated height or not; 4 to 5× cheaper than SwiftTUI where both grow.
2. Memory.
3. First frame: about 4 to 10× quicker on bounded pages (0.07 against 0.31 s for hello, 0.12 against 1.05 s for 1,920 cells), far more when unbounded.
4. Deep trees degrade without a crash.
5. A fully silent idle page.

**Where TUI should act, in order of value** [I].
1. **Stop re-running plain bodies whose inputs did not change, and stop running them twice.** The clearest user-visible gap, and a SwiftUI program would misbehave here in a way that it does not on SwiftUI. Until then, say so on an author-facing page (Q32) and point at `.equatable()`.
2. **Blend and opacity compositing path:** study their span walk; aim to match on `lat-blend`. Not threads first.
3. **Focus pulse at idle:** decide. It is TUI's only poor idle number.
4. **Memos on ancestor writes:** `tree-root` at 20 ms is fine, and `lat-heavy` runs at 24 fps, so this stays a known cost, not urgent.
5. **Scroll-region output:** nice to have, M, with survey work.
6. **Blank page past the depth limit:** say why.

**Limits of this evidence.**
- One machine, shared, a VM. Synthetic scenes of my own. Same-source fairness hides that SwiftTUI apps might be written differently, with `.equatable()`, for instance, which I did not try.
- The 1,920-cell page is large; a typical app page has 50 to 300 views, where SwiftTUI costs 7 to 20 ms a key and feels fine.
- I did not exercise SwiftTUI's `.equatable()` boundaries, browser hosts or real apps. TUI's `.equatable()` was not tried on the slow-sibling case either; its docs say it would memoize [S].
- The later fairness runs (stated height, slow siblings, `fan-leaf`, scroll) ran under load 16 to 69, higher than the earlier ones. Their times are worse for both frameworks; compare within a table, not across tables.
- After the 25 GB peak I added a guard that kills past 8 GB. It killed one run (`Table` of 10,000 in the scale table), so that cell is empty. The guard is mine, though the growth is theirs.
- Causes marked [I] are from samples and source, not proofs.


---

## Q30. Size

Equivalent apps, one source each (`gen/generate.py`), Swift 6.4.0, macOS arm64, `swift build -c release`, then `strip` with no options. On 6.4.0, `swift build` on macOS uses Swift Build by default; I kept that for both. [M] throughout.

| App (equivalent) | TUI, `TUI` product | TUI, selective | SwiftTUI, `SwiftTUI` default | SwiftTUI, terminal-only (`SwiftTUIRuntime` + `SwiftTUICLI`) |
|---|---:|---:|---:|---:|
| Hello world | 13.52 MB | **8.56 MB** (`TUIApp`) | 22.19 MB | 21.45 MB |
| Counter with a button | 13.54 MB | **8.56 MB** (`TUIApp`) | 22.19 MB | 21.45 MB |
| List with selection | 13.54 MB | **9.30 MB** (+`TUILists`) | 22.19 MB | 21.45 MB |
| Mid-size: table, sheet, text field, tabs | 13.54 MB | **10.79 MB** (+`TUITables`, `TUITabs`, `TUIPresentation`, `TUITextInput`) | 22.21 MB | 21.47 MB |
| Large, each its own, **not equivalent** | 17.04 MB: `Example`, 34,050 lines; 15.34 MB: `Stress`, 17,080 lines | | 23.60 MB: `gifeditor`, 18,900 lines | |
| `__text` of hello | 10.59 MB | 6.57 MB | 17.37 MB | 16.78 MB |
| Unstripped hello | 29.98 MB | 18.83 MB | 45.19 MB | 43.77 MB |

**With `-Xlinker -deduplicate`, then `strip`** (relinked; `ShippingAnApp.md` lists the cost: some key paths and closures compare equal):

| App | TUI `TUI` | TUI selective | SwiftTUI default | SwiftTUI terminal-only |
|---|---:|---:|---:|---:|
| Hello | 12.52 MB (-7%) | 7.95 MB (-7%) | 20.77 MB (-6%) | 20.10 MB (-6%) |
| Mid-size | 12.54 MB (-7%) | 10.01 MB (-7%) | 20.77 MB (-6%) | 20.10 MB (-6%) |

**What must ship beside the executable.**

| | TUI | SwiftTUI |
|---|---|---|
| Resource bundle | `TUI_TUIStrings.bundle`, 92 KB, optional (translations, version) | `swift-tui_SwiftTUIWebHost.bundle`, 264 KB, for `--web` only; terminal-only has none |
| **Library needed to launch on macOS before 26** | **None** [M: `otool -L`; CI enforces it] | **`libswiftCompatibilitySpan.dylib`, 157 KB, in every SwiftTUI binary** [M] |

**That last row is a real shipping defect in SwiftTUI on its own floor.** The binary finds the library through an rpath into the toolchain that built it. On a machine without that toolchain, on macOS 15 (its stated minimum), it stops at launch. I reproduced it here on macOS 15.8.1 by removing those rpaths: `dyld: Library not loaded: @rpath/libswiftCompatibilitySpan.dylib` [M]. Copying the dylib beside the executable fixes it [M]. `Distributing-Your-App.md:33-35` calls the executable "the deliverable" and does not mention it; a search of their docs finds no mention [M: grep]. Which dependency pulls it in I did not determine; TUI's own doc names swift-collections 1.4 and later, and SwiftTUI uses 1.7.5 [V]. TUI's `ShippingAnApp.md` documents exactly this, and its CI gate keeps TUI clear of it.

**What the numbers mean.**
- **TUI's hello is 39% of SwiftTUI's default on selective modules, and 61% on the umbrella.** Selective TUI at mid-size is about half of SwiftTUI's smallest.
- **SwiftTUI has no useful selective build.** Going terminal-only saves 0.74 MB, 3%. It does not use less of the view library. Its `SwiftTUIViews` is a single module, and its size does not change between hello and the mid-size app: **all of it stays**. Its size is essentially constant (21.45 to 21.47 MB), which shows the linker cannot drop unused views.
- **TUI's size also moves little under the umbrella** (13.52 to 13.54), as expected: the umbrella brings everything. Its module split is what works: 8.56 to 10.79 MB as you add modules.
- **The web host itself is small:** 0.74 MB plus the 264 KB bundle. The evidence report's worry about it was overstated.
- **Figlet fonts and vendored libraries:** I did not separately size them, but they are in the 21 MB.

**Clean release build** (`-j 6`, machine shared, load 15 to 30 at the time; CPU is `user + sys` from `/usr/bin/time -l`, which is steadier than wall time):

| Build | Wall | CPU | Peak RSS of one process |
|---|---:|---:|---:|
| TUI hello, selective (clean) | 292 s | **326 s** | 3.2 GB |
| TUI, rest of the modules on top | 106 s | 249 s | 0.6 GB |
| **TUI, everything** | about 400 s | **575 s** | |
| SwiftTUI hello, terminal-only (clean) | 536 s | **595 s** | 2.8 GB |
| SwiftTUI, web host and default product on top | 47 s | 91 s | 0.7 GB |
| **SwiftTUI, everything** | about 580 s | **686 s** | |
| Disk for the scratch directory, without dSYMs | TUI 919 MB | SwiftTUI 944 MB | |

So **a selective TUI build uses about 55% of the CPU of SwiftTUI's smallest**, and an everything build 84%. One build each under load, so treat as rough. SwiftTUI's clean build includes fetching and compiling its three package dependencies; TUI's selective has none of those to compile.

**TUI on Xcode's Swift 6.2.4**, with its native build system, for comparison:

| App | `TUI`, stripped | Selective, stripped | 6.4.0 was |
|---|---:|---:|---:|
| Hello | 13.67 MB | 8.78 MB | 13.52 / 8.56 |
| Counter | 13.67 MB | 8.78 MB | 13.54 / 8.56 |
| List | 13.67 MB | 9.52 MB | 13.54 / 9.30 |
| Mid-size | 13.68 MB | 10.95 MB | 13.54 / 10.79 |

Its clean build of everything took 436 s wall and 599 s CPU. One run, under load.

**TUI's docs versus today.** `ChoosingProducts.md` says about 40% smaller for `TUIApp` versus `TUI`. Measured on 6.4.0 here: 37% (13.52 to 8.56 MB). Accurate.


---

## Q31. Tests and benchmarks SwiftTUI has that TUI lacks

Real gaps only, read from both repositories [V]. Effort: **S** days, **M** one to two weeks. I left out what TUI already covers in another form: golden snapshots, storm suites, the memo verifiers in `Stress --selfcheck`, `ab_bench.py`'s noise floor (their `AAEnvelope`), `emit_bench.py` (their emission lane), `Tools/DedupCheck`, `Tools/APIParity`, and `check-span-compatibility`.

| # | What they have | What TUI has | What it would catch | Effort |
|---|---|---|---|---|
| 1 | **Input-to-frame latency as a tracked number.** `input to commit p95 ms` is a gate metric in `PerfGate.swift`, with scenarios `ScrollNotchLatency`, `ScrollCadence60Hz`, `ScrollFlingMomentum`, `SheetOpenLatency`, `TextInputEditing` | `page_open.py`, `animation_rate.py`, `idle_cpu.py`. No latency percentile under a scripted input stream | A change that keeps frames cheap yet delays them: a pacing mistake, one more walk per key. Q14 shows how much this measure tells. `engine/scripts/driver.py` here is a start | S to M |
| 2 | **Committed counter baselines checked in CI.** `Baselines/bench-counters.json`: draw nodes, measures, cells presented, frames, per scenario, debug and release | `MemoCounts` and `--census` print counts for a person to read, and nothing is committed or compared. CI builds `TUIBenchmarks` and never runs it | A work regression on a loaded CI box, where times are useless (`timing-budgets-and-allocation-oracles`). Allocation counts work well here: in Q14 they repeated to 0.1% across runs | M |
| 3 | **Tests run in release, with the invariant checks forced on.** `release_soundness_lane.sh`, nightly and on tags. Their reason for it: release-only behaviour had shipped unobserved | CI runs `swift build -c release` and tests debug. Release with `-enable-testing` is a local sweep only | Anything that differs under `-O`: exclusivity, inlining, or a verifier not armed. Your note `release-build-closure-specialization-blowup` shows debug hiding real trouble. Note that TUI's verifier env vars do not need a test build | S |
| 4 | **Automated differential against real SwiftUI in CI.** `Tools/PublicSemanticOracle.swift` compiles the same fixture against both, drives `NSHostingView`, diffs event order, stamps the OS and toolchain, and refuses silent updates. 6 fixtures only | `Tools/SwiftUIProbes`: 60 topics, far more behaviour, run and recorded by hand | A SwiftUI update changing behaviour, or a TUI change drifting from a recorded answer. Turning your 60 probes into runs is worth more than their 6 fixtures | M |
| 5 | **Property tests with shrinking.** `SeededRandomSource`, `Gen`, `checkProperty(... maxShrinkSteps:)` in test support; `AdversarialSetG` properties (100 iterations, 1,000 under `SWIFTTUI_STRESS_FULL=1`) | Seeded storms (`FocusStorm`, `DragAndDropStorm`, `TextInputStorm`, `MultiSelectionStorm`) with no shrinking | Same bugs as storms, but a failure arrives as a minimal case rather than a long seed run | S to M |
| 6 | **Per-cache growth over a run.** `MemoryGrowthAnalyzer` samples each cache's count, fits a slope and excludes plateaus, flagging each provider that keeps growing. Plus `AnimationRepeatForeverGrowthTests`, `AnimationLongRunLeakProbeTests` | `ProcessMemory` totals and `AccumulateSession` for one mechanism. Your unbounded-growth lane on 10-29 found its 5 cases by hand (`QUEUE.md:1272`) | Bounded-but-too-big or slow-leak caches, named by provider rather than as a rising total | S to M |
| 7 | **A ratchet against sleeps in tests.** `check_test_sync_policies.sh`, baseline 16, one way | I count 58 uses of `Task.sleep`, `usleep` or `Thread.sleep` in 24 test files [M: grep]; they have 11 [M]. No lint | New timing flakes, which your notes record repeatedly (`timed-wake-tests-race`) | S |
| 8 | **Per-test duration ratchet.** `check_test_durations.sh` warns at 10 s, fails at 2× | `test-suite-runtime-plateau` note, by hand | A slow test creeping in | S |
| 9 | **Re-run of a registry of known async-flaky tests under load.** `repeat_async_flake_registry.sh` | `parallel_test.py` reconciliation, not repetition | A flake fix that did not fix it | S |

**Not gaps, though it looks otherwise.**
- **"Fuzzers":** the "gallery fuzzer" named in their tests lives in a private repo. The public tree has seeded property tests only. Neither project has a coverage-guided fuzzer, and neither fuzzes the input parser as far as I found.
- **The soundness oracle map** (`docs/SOUNDNESS-ORACLES.md`, 30-odd probes, armed in release too at 1 frame in 256): most of those invariants guard machinery TUI does not have (checkpoints, graph teardown, retained stamps, drafts). Its value is the discipline, not the list. The one to borrow is **raster damage**: the incremental result equals a fresh one, run in production builds on a sample of frames. Your `TUI_VERIFY_RENDER_MEMO` is the same idea but armed by env var only. Sampling 1 in 256 in release would catch memo bugs at users' sites, for about S. It would need a report channel, which TUI lacks: their `RuntimeIssueSink`.
- **`check_tree_walker_recursion.sh`, `check_layout_work_stack_guardrails.sh`:** needed because their worker has a 512 KiB stack. TUI has no worker.

**Worth doing first:** 2 and 7, for little effort; then 1.

---

## Q32. What their performance docs say, and what TUI can learn

I read `Performance-For-App-Authors.md`, `Runtime-Render-Pipeline.md`, `Hosts-And-Platforms.md`, `docs/ARCHITECTURE.md`, `docs/SOUNDNESS-ORACLES.md` and the changelog. Cross-checks are against Q14.

### Their claims, cross-checked

| Claim | Where | Check | Verdict |
|---|---|---|---|
| "Most SwiftTUI apps never need performance work" | Authors `:8` | Small page: 7 ms a key, 40 cells; 116 ms at 1,920 cells [M] | True for small pages only |
| "redraws only the terminal cells that actually changed" | Authors `:9-10` | 209 bytes for a leaf change, and the marker in it is a cell run [M]. Its diff truly is cell-level | **True**, and TUI's is equally tight (40 bytes for the same frame's marker) |
| Lazy containers "build only the rows that are visible (plus a small margin), no matter how long the underlying list is" | Authors `:10-12`, Pipeline `:317-351` | `ScrollView { LazyVStack }` of 10,000: first frame 0.5 s, 57 MB [M]. With a stated height, `List` and `Table` are flat in N [M]. **Under a `VStack` with no height, cost per key rises with N**: 39, 157, 1,556 ms at 100, 1,000, 10,000 (`List`) [M]; `Collections.md:157-161` documents this as "unbounded height", but the performance page does not | True given a bounded height. The page should say so, since a SwiftUI author will not state one |
| "Fifty screen-blended ripples at 180 × 60 cost 131 ms per release frame" | Changelog `:749` | Mine: 30 full-screen blended gradient layers at 200 × 50 run about 0.6 s a frame [M]. Different scene; same order given the layer sizes [I] | Plausible |
| "A 10,000-row table's first frame went from ~68 s to ~360 ms" | Changelog `:2355` | Mine: 22 s and 3 GB in a `VStack` with no stated height; 0.60 s and 49 MB with one [M]. Their case is `ScrollView { Table }` | Plausible for their shape. Unbounded remains very slow |
| "Large-tree frames resolve 14-17% faster" | Changelog `:1832` | Resolve is 6.5% of a leaf frame on the main thread here [M: sample] | True and small: resolve is not the bottleneck any more |
| Off-main tail frees the main actor | Pipeline `:283-286` | True on the blend case only (979 versus 1,566 ms), no benefit or worse otherwise [M] | Partly |
| Completed-frame dropping | Pipeline `:241-248` | **0 frames dropped** in 12 traced runs, 8 under real load; each frame reads `blocked` or `commit_ordered`. Cancelled before start: 7 of 31 on `lat-blend`, 23 of 46 on `lat-heavy` [M] | Present, inactive in what I ran |
| Iterative layout, "Every tree walker reachable from the tail is an explicit-stack loop" | Pipeline `:164-168` | Crashes in `FrameTailRetainedInput.collectReusablePhaseSubtrees`, a self-recursive frame stack on the worker, near depth 200 [M] | Their own doc concedes value destruction; this frame is not destruction, so the claim is at least incomplete. Cause not proven |
| Idle sleeps on a read source | `InputPollBackoff.swift:3-5` | Reader does. But an app idles at about 1% CPU and 45 wakeups a second [M], from `SceneDiscoveryServer`'s 20 ms accept poll on 3 threads (`SocketServer.swift:271-290`) [V, sample] | Partly |

### What TUI can learn from them

1. **An author-facing performance page.** Theirs is 200 lines and gives four levers: `.equatable()`, stable identity, lazy containers under a `ScrollView`, and measure first with a named tool. TUI has `RenderCycle.md`, which is about internals, and no page saying what an author can do [M: `ls`]. The fact that a plain view's `body` runs on every frame, twice, is what such a page most needs to say, given Q14's result. **S.**
2. **A shipped profiling switch.** `.profiling()` under `SWIFTTUI_PROFILE=frames`, plus `SWIFTTUI_FRAME_TRACE=<path>`, which I used here: it answered "was that frame cancelled?" in one line. TUI has `TUI_DEBUG_RENDER` and `Tools/Profiling`, both for you rather than the app author. A `TUI_FRAME_TRACE` writing a TSV of cause, memo hits and bytes is **S to M**, and would help support.
3. **Scroll-region output** for full-width scrolls: 290 bytes against about 10 KB a notch for dissimilar rows [M: Q14 (b)]. It is a real win on slow links only. See Q14 for how.
4. **Separate input from invalidation in pacing.** `SWIFTTUI_MERGE_PRESSURE_PACING` documents the right idea: wheel and keys bypass the pacing gap. TUI's pacer caps all alike [V: `FramePacer`]. Its cost at 60 Hz is small; worth a look only if a scroll complaint appears.
5. **A/A envelope in the tool, not the docs:** you have a noise-floor table in a README; they store it per scenario. **S.**
6. **`RenderOnce` and `--stable-output` as first-class** help CI, and were in the earlier report.

### Where SwiftTUI is notably better on design

- **Output.** Scroll regions, proper cell spans everywhere, and damage kept apart from reuse. Nicely argued in the doc (`Pipeline:361-407`, on why the diff basis must be the draw tree).
- **Heavy compositing.** Its per-paint blend walk is about 2.5× TUI's on my blend case [M], from dedicated span work (`CHANGELOG:745-749`). TUI could study this. Its own numbers show years of effort going to this path: "visit only the rows and spans inside the transparent support".
- **Clarity about limits.** Stated budgets, an honest register, and a typed frame record.
- **Separation of concerns.** Pure phase products and a typed pipeline, which also make hosts other than terminals possible. This is where most of its engine cost goes, by design: the same semantic and raster frames feed browser, Android and SwiftUI hosts. So some of what looks like waste here buys those hosts [I].

### Where it is notably worse

- **Cost per frame scales with the whole tree, not with what changed**: Q14 (a). Every frame copies, checkpoints and walks: 470,000 allocations for a one-leaf press at 1,920 cells [M]. This is the central design cost of immutable phase products with retained state.
- **Memory:** level at hello, 8 times TUI's at 1,920 cells, 3 to 5 times with a bounded 10,000-row list or table, 37 to 280 times when unbounded [M].
- **`List` and `Table` with no bounded height:** see above. Peak 25 GB in one table run [M]. A stability hazard in practice, for code a SwiftUI author would write without thinking. It does report `collection.unboundedRealization`, once [S]; I discarded stderr, so I did not see it.
- **Deep nesting** is less robust than TUI's, despite the design aim [M].
- **`.task` loops writing every 16 ms cost a lot** because each write is a whole frame [M: `anim-tick`, one frame every 4 s].


---

## Q15. Strict memory safety

**What it is.** SE-0458, opt-in, available from Swift 6.2. `.strictMemorySafety()` in a manifest passes `-strict-memory-safety`. The compiler then warns (group `StrictMemorySafety`) wherever code uses something declared unsafe, unless the expression is marked `unsafe`. It adds no runtime check and changes no generated code; it only makes the unsafe places visible and greppable. It covers pointers, `unsafeBitCast`, `nonisolated(unsafe)` reads, `@exclusivity(unchecked)`, `unowned(unsafe)`, and C types holding pointers. It does not make anything safe. A wrong pointer calculation under `unsafe` is just as wrong.

[M] A small test confirmed the "no code change" part: the same function with and without `unsafe` gave identical `-O` assembly on 6.4.0 (`q15/safe/`).

**What SwiftTUI did** [V].
- `.strictMemorySafety()` is in the shared settings of every target (`Package.swift:99`).
- A clean build emits no such warnings [M: 0 lines in the release build logs].
- It writes `unsafe` on about 750 lines in `Sources`, `Platforms` and `Tools` [M: grep]. The most are in the runtime (161) and `Platforms/CLI` (144).
- It has a handful of `@unsafe` declarations, mostly its reflection plans (`MemoFieldComparator`, `DynamicPropertyUpdatePlan`, `FieldReflectionMetadata`).
- It has 9 `@unsafe @preconcurrency import Dispatch` lines.
- `Scripts/check_concurrency_safety_policies.sh` bans `@safe` too, so no one can silence the checker by claiming a type safe.
- `AGENTS.md:90,124` state the rule for contributors.

### Trying it on TUI [M]

I type-checked each module of my clone with `-strict-memory-safety`, Swift 6.4.0, against the modules already built. Nothing was edited. This was `swiftc -typecheck`, not a build, so it ran outside a build slot. Results and logs are in `q15/`. The 2 modules that did not type-check were left out: `TUIMacrosPlugin` (no swift-syntax here) and `TUIFilePanelsAppKit` (1 setup error).

**1,080 unique diagnostic sites in 19 of the 32 modules checked.** The other 13 have none, which matters: the feature modules are almost clean.

| Module | Sites | Why |
|---|---:|---|
| `TUIView` | 443 | Reflection: `ValueHashPlans` 72, `ObservationLeases` 37, `PropertyWalk` 35, `DynamicTypes` 33, `FieldDescriptors` 33, `BodyWitnessMemo` 32 |
| `TUIApp` | 138 | `FatalSignalTerminalRestore` 69, `Terminal` 17, input buffers |
| `TUIFoundation` | 128 | `ANSIRenderer` 26, `ValueHashOpeners` 20, `SGRColorRewrite+NumericReading` 19 |
| `TUICore` | 117 | `VolatileReadTracker` 26, `String+SGRCollapsing` 22, ANSI scanning |
| `TUIImage` | 107 | `ASCIIConverter+Dithering` 29, `RGBAImage` 23 |
| `TUIStyling` | 43 | `Color+Downsampling` 15 |
| Other 13 | 104 | `TUIStrings` 21, `TUITerminalHost` 19, `TUITables` 17, `TUIBitmaps` 13 |

| Kind of diagnostic | Sites |
|---|---:|
| "expression uses unsafe constructs" (add `unsafe`) | 1,042 |
| "for-in loop uses unsafe constructs" | 18 |
| A struct or class "has storage involving unsafe types" | 16 |
| A conformance "involves unsafe code" (4 `EnvironmentKey` defaults) | 4 |

What the expression notes point at, counting each note:
- A value of an `Unsafe*` or C pointer type: 2,221 notes, about 90% of the total.
- A read of a `nonisolated(unsafe)` global: 148.
- `@exclusivity(unchecked)`: 20.
- `unsafeBitCast`: 18.
- `unowned(unsafe)`: 2.

**Toolchains.** On Xcode's 6.2.4, `TUICore` alone gave 134 sites against 117 on 6.4.0 [M]. The flag works on 6.2, and the counts differ by toolchain, so a clean build on 6.4.0 is not automatically clean on 6.2. In my small file, `xs.withUnsafeBufferPointer` needed one more `unsafe` on 6.2.4 than on 6.4.0 [M]. Marking both sides is harmless, but all of 6.2.4, 6.3 and 6.4 would have to be clean.

### Cost and benefit

**Cost** [I, from the counts].
- About 1,060 of the sites are mechanical, since each comes with a fix-it inserting `unsafe`. Applying them is about a day, then a pass over 6.2 and 6.3 for the differences.
- The 16 storage and 4 conformance sites need a decision: `@unsafe`, or encapsulate. The 4 conformances vanish with the `N-default` fix in Q16.
- The token noise lands on the hottest code you own: the ANSI scanners, `ValueHashPlans`, dithering.
- Lint limits may tip on files near 600 lines.
- No runtime cost, by the assembly check above.

**Benefit for TUI specifically.**
- A written inventory. `grep unsafe` becomes the complete list of what can corrupt memory, and with your zero-warnings policy any new one must be spelled out at the site.
- The concentration is informative: about 40% of it is `TUIView`'s reflection, 6% the signal handler. Reviewers of those two areas are exactly who should read it.
- It would not have prevented the bugs you recorded: reading uninitialised bytes, and hashing padding (memory note `never-read-uninitialised-bytes`), would still compile under `unsafe`. Those are found by your verifiers and tests.
- It says nothing about data races, which is Q16.

**Conflicts checked.**
- **Swift 6.2 floor:** no conflict. `swift-tools-version: 6.2` accepts `.strictMemorySafety()`, and `unsafe` parses there [M: compiled on 6.2.4].
- **Performance-sensitive buffers:** no conflict. `unsafe` is a marker, with identical code.
- **`Span`:** it is the tempting way to shrink the count, since `Span` needs no `unsafe`. On your floor it is blocked. `Span` from the standard library pulls in `libswiftCompatibilitySpan.dylib` before macOS 26, and `Tools/check-span-compatibility.sh` fails CI on that deliberately. SwiftTUI shows what happens otherwise (Q30): its binary links that library and fails to launch here on macOS 15.8.1 once the toolchain path is gone [M]. `InlineArray` in `TUIStyling` and `TUIView` is fine, and already used.
- **`@exclusivity(unchecked)`:** flagged at 20 sites, as it should be. Just mark them.

**My recommendation.** Worth adopting at low priority, as a tidy-up day after the main-actor lane settles, because that lane will remove many of the 148 global reads. Do not expect it to find bugs. Adopt `TUIView` and `TUIApp` last, once the rest is clean, with a `-Werror StrictMemorySafety` lane on 6.4 only.

---

## Q16. Unsafe concurrency

**Scope.** Real declarations in `Sources`, comments excluded: **114 `@unchecked Sendable` and 55 `nonisolated(unsafe)`**. Plain grep says 147 and 73, because comments mention them. `q16/census.py` found them, and `q16/classify.py` assigned each by name; `q16/census-by-class.txt` lists all 169. The classes are my reading of each declaration and its comment. I read the comment and neighbouring code, not every use, so treat the split between `U-service` and `U-box` as approximate.

### `@unchecked Sendable` (114)

| Class | Count | Representative | Remove how |
|---|---:|---|---|
| **Service:** per-app or per-frame object, main thread, no lock | 35 | `TUIView/State/StateStorage.swift:37`, `TUIFoundation/Focus/Focus.swift:47`, `TUIView/Rendering/RenderCache.swift:95` | `@MainActor`. This is the migration lane's work: leave it. Mixed ones (`StateBox`, `RenderCache.Link`) have a truly off-main write path, handled by a lock |
| **Lock:** the state is behind a lock, and the class just cannot prove it | 26 | `TUICore/Concurrency/Lock.swift:21`, `TUIFoundation/Environment/TUIContext.swift:20`, `TUIStyling/Color/LightDarkColor.swift:132` | Floor 15: `Mutex` in a `let`, then plain `Sendable`, where **all** mutable state moves inside it. About 20 of the 26 [I] |
| **Payload:** a value holding a closure, `AnyHashable`, existential or generic | 22 | `TUICore/Environment/EnvironmentKey.swift:75`, `TUIFoundation/Styles/StyleChain.swift:25`, `TUIFoundation/StatusBar/StatusBarItem.swift:197` | Mostly **keep**. Removing means demanding `Sendable` from app values, which SwiftUI does not (see below) |
| **Box:** a mutable box a render refreshes and an event closure reads | 21 | `TUIFoundation/Environment/DismissAction.swift:74`, `TUIFoundation/Views/ScrollView.swift:275` | `@MainActor`: lane |
| **Immutable:** all `let`, of types the compiler cannot prove | 7 | `TUICore/Animation/Transaction.swift:301`, `TUIImage/ASCIIPalette+SearchIndex.swift:53` | Keep; some can drop it once their field types are `Sendable` |
| **Tools:** `Example`, `Stress` | 3 | `Stress/StressApp.swift:21` | Trivial, low value |

### `nonisolated(unsafe)` (55)

| Class | Count | Representative | Remove how |
|---|---:|---|---|
| **Memo:** process-wide cache beside an `NSLock` | 16 | `TUIStyling/Theme/RowFills.swift:153`, `TUIStyling/Color/Color+PulseRamp.swift:289`, `TUIBitmaps/Styling/AssetCatalog.swift:108` | Put the dictionary **in** the lock. Works today with the existing `Lock<T>`; on floor 15 with `Mutex`. No floor change needed. I checked uses for most: the neighbouring `NSLock` guards them. The compiler then enforces what is only a convention now. A few (`noted`) are thread-gated rather than locked |
| **Signal:** read by the fatal-signal handler | 12 | `TUIApp/App/FatalSignalTerminalRestore.swift:160` | **Keep.** A lock in a signal handler is wrong; the allocations are done up front, deliberately. Counters could be `Atomic`, the pointers cannot |
| **Flag:** a process-wide capability or generation, written at startup or between frames, read anywhere | 12 | `TUIStyling/Color/ColorDepth.swift:83`, `TUICore/Extensions/KittyGraphics.swift:342`, `TUICore/Extensions/TerminalWidthTraits.swift:236` | Floor 15: `Atomic<Bool>` and `Atomic<Int>`, relaxed. Plain-load cost on arm64 and x86 [I]. A struct value (`TerminalColors`) goes in a `Mutex`. These are formally data races today, the only class here where the fix changes what is true, not merely what is proved |
| **Local:** `nonisolated(unsafe) let x = x` to cross a closure | 7 | `TUIFoundation/Views/Button.swift:774`, `TUITabs/Views/TabStripHandler.swift:90`, `TUITables/Views/TableOutline.swift:238` | Gone when handlers are `@MainActor`: lane |
| **Default:** an immutable `EnvironmentKey` default | 4 | `TUILists/Views/EditMode.swift:48`, `TUINavigation/Views/NavigationSplitViewResize.swift:61`, `TUIFoundation/Views/ScrollAnchor.swift:99` | **Trivial, today:** `static var defaultValue: X? { nil }`. The requirement is `{ get }` (`EnvironmentKey.swift:34`), and a computed static needs no `Sendable`. Also removes 4 strict-safety conformance diagnostics |
| **Exempt:** a public static | 2 | `TUIChrome/Notification/NotificationService.swift:117`, `TUIFoundation/State/AppStorage.swift:311` | Owner ruling A-APPSTATE-2 made them. Could sit in a `Mutex`, but `@MainActor` may break the parity shape. Leave |
| **Field:** an immutable field of a non-`Sendable` type | 2 | `TUISearch/Environment/SearchPresentation.swift:67`, `TUITables/Views/TableOutline.swift:61` | Keep or lane |

### Summary of what could go

| Route | Sites | Effort |
|---|---:|---|
| Today, no floor change: 4 defaults, 16 memos into `Lock<T>` | **20** | S, about a day |
| Floor to macOS 15: about 20 lock classes, 12 flags | **about 32** | M: mechanical, but `Lock` has 14 users and 29 raw `NSLock()` exist. Measure the `Mutex` versus `OSAllocatedUnfairLock` cost first; I did not [not measured] |
| Main-actor lane: 35 services, 21 boxes, 7 locals, some fields | **about 63** | Already in progress: do not duplicate |
| Stay: 12 signal, 2 exempt, most of 22 payload, immutables | **about 40** | Each has a reason; a comment on each already exists for most |

**The payload class is the real difference from SwiftTUI**, and it is why a total ban is not free for TUI. SwiftTUI makes the compiler right by narrowing what apps may write: environment models must be `Sendable` (REG:148), `Binding` closures `@MainActor` (REG:155), and `ForEach` IDs `Sendable` (REG:226). `Layout` is `Sendable` too. TUI's `EnvironmentKey.Value` and `EnvironmentValues` take what SwiftUI takes, so they carry the `@unchecked`. The evidence report recorded the cost: an `@Observable` without `@MainActor` does not compile on `.environment` there.

### How SwiftTUI enforces its ban, and what it does instead [V, M]

**Enforcement.** A 25-line script, `Scripts/check_concurrency_safety_policies.sh`, greps `Sources`, `Tests`, `Platforms` and `Tools` for `@unchecked Sendable`, `nonisolated(unsafe)` and `@safe`. It is a text ban, and it held: I found **0** of each in Swift sources. The only hits are in `Scripts/data/value-type-invariant/rejected.swift`, a negative fixture.

**Does it hide equivalents?** Partly, and honestly:

| Construct | SwiftTUI | TUI, for scale |
|---|---:|---:|
| `Mutex<` | 64 | 0 (uses `Lock<T>`, `NSLock`) |
| `Atomic<` | 7 | 0 |
| `MainActor.assumeIsolated` | 22 (a checked trap, sound) | 32 |
| `@preconcurrency` | 14, of which 9 are `@unsafe @preconcurrency import Dispatch` and the rest conformances (`TerminalInputReading`, `SignalSourceArming`, ...) | 32 |
| `unsafeBitCast` | **2**, both hot-reload `dlsym` results (`HotReloadLoader.swift:125,162`) | 20 |
| `Unsafe*Pointer` type mentions; `withUnsafe*` calls | 126; 111 | 237; 97 |

So there is no hidden `unsafeBitCast` to `Sendable`, and no wrapper type named `UncheckedSendable` or similar. But `@preconcurrency` conformances do switch off the static isolation check at those boundaries, leaving a dynamic one. Their reflective memo (`@unsafe MemoFieldComparator`, `RuntimeFieldReflection.swift`) reads arbitrary fields through raw pointers just as TUI's `ValueHash` does; it is marked rather than absent.

**What the ban costs them at runtime** [V, M]. Their own doc: automatic flattening of deep trees "requires a `Mutex` for reads of that class. This cost is not acceptable" on the hottest accessor (`Runtime-Render-Pipeline.md:186-188`), so a deep tree can still crash on destruction. The crash I measured at depth 200 is on that worker (Q14). This is the same trade-off, paid at a different place.

**What TUI could take:** the script itself, as a ratchet on the count rather than a ban: CI fails if the count of `@unchecked Sendable` rises. It costs nothing, and it holds the lane's gains. About S.
