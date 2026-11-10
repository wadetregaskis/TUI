# Performance pass, November 2026

**Measured 2026-11-08** on macOS 15 / arm64 (the VM, Xcode 26 SDK), release builds
with `-Xswiftc -g`, starting from `a98a4b8db`. The owner asked for work on CPU,
render latency and RAM. A dated record: symbols are as named on the day.

## Method

- **Frame cost:** `Tools/Profiling/ab_bench.py`, CPU per frame, 10 reps of 4.5 s,
  each change against its parent (`perf/build_v.sh` builds). The machine was not
  idle (load 2–5, a window server taking most of a core), which `ab_bench`'s CPU
  time and paired ratios are built for.
- **Where the time goes:** Time Profiler traces read with
  `analyze_timeprofile.py`: the Example driven through `record.sh`
  (`tour`) and `drive.py` (`list`), the Example idle on a page, and `Stress
  --bench` on the heaviest scenarios and sessions.
- **RAM:** `Stress`'s `rss-peak`, and now the Example's own peak resident set
  over a scripted session: `drive.py` prints `peak-rss=` and `cpu=` from the
  `wait4` that reaps the app (`24c931c07`). `footprint` and `heap` on a live
  Example for what is held.
- **Render latency:** `input_latency.py`, key to the end of the frame showing it.

## Baseline

| Measure | Value |
|---|---|
| Heaviest scenarios, µs a frame | gradients 23,791 · pickers 15,067 · app-shapes 9,947 · churn 8,951 · alpharamp 8,745 · texteffects 7,519 · geometry 5,196 |
| Heaviest sessions, µs a frame | notes 7,108 · settings 5,729 · menus 4,478 · log 3,383 · chat 2,588 |
| Stress RAM | 13–46 MB a scenario (alpharamp the most) |
| Example peak RSS | tour 83–90 MB; one page (list, table, emoji) 44–48 MB |
| Example footprint | 13 MB on its menu; 56 MB back on the menu after the tour |
| Input to frame, p50 | table 13.1 ms · scroll 17.6 · mouse 12.9 |
| Idle | 0.2–0.5% CPU on most pages; Tables 4.7% (2.5 frames a second) |

Two of the tools were broken on the way in. `drive.py` and `input_latency.py`
quit the app with `q`, which has been an ordinary key since ⌃Q became the quit
shortcut (2026-10-31), so every scripted run ended in "the app did not quit" and
`record.sh` could not finish (fixed, `39fd31d5f`). And the `list` scenario's arrows no longer
reach a list: its "latency" of 56 ms is the next frame of the focus ring's
breathing, 50 ms apart, not an answer to the key. Not fixed here; since fixed
in the scenario (the next section's follow-ups).

## What the profiles said

1. **The menu bar.** Every walk of an app with commands renders each closed
   menu's items for the shortcuts they register, and throws the drawing away
   (`_MenuBarCore.registerShortcuts`): 11.2% of the Example's tour, 15.4% of
   its `list` frames, 20% of its idle frames on the Tables page. No scenario and
   no session drew a menu bar, so `ab_bench` had never seen it.
2. **Identity paths.** A focusable control's default focus id is its identity
   path, and the path wrote every generic type whole: tens of kilobytes for a
   control a few dozen views deep, kept for as long as the control is and hashed
   each frame. After the tour, 11.6 MB of the Example's heap was strings; one
   visit to the Buttons page left 6.4 MB of them.
3. **First sight of a type.** The value-hash plans and the other per-type walks
   ask the runtime about protocol conformances, which on a type's first sight
   scans every conformance record: `swift_conformsToProtocolMaybeInstantiateSuperclasses`
   is 10.6% self of the tour, `ValueHashPlans.insertPlan` 8.7% inclusive. A cost
   paid once per type per process: a page's first opening. Not changed here.

## What changed

| Commit | What | Measured (`ab_bench.py` against the parent unless named) |
|---|---|---|
| `7b0835148` | the `inbox-commands` session: the inbox under a menu bar, so `ab_bench` sees one | a frame: select 1,969 → 3,571 µs, arrive 1,295 → 3,229 µs against `inbox` |
| `13837abc6` | a closed menu's rows render for their shortcuts without a measure first | `session/inbox-commands` −12.2% |
| `3a92f5edb` | a picker registers nothing such a render keeps, so it draws nothing there | `session/inbox-commands` −20.5% (−30% with the one before) |
| `4daf7f366` | an identity path writes a generic type's arguments as a digest, `ModifiedView<9f3a…>` | Example tour: peak RSS 81.5 → 68.8 MB, CPU −3.7%; footprint after the tour 56 → 39 MB; `session/menus` −7.8%, `settings` −3.5%, `notes` −2.4%, `chat` −2.2% |

The menu bar's share of an `inbox-commands` frame went from 34.7% to 11.6%.
What is left is mostly the buttons' own drawing (2.2%) and the planting of
their shortcuts (5%).

## Left as it was

- **First sight of a type** (above): diffuse across every per-type walk; the
  lever is fewer conformance questions per type. Page-open latency, once per
  page per process.
- **The Example's file browsers** read the home directory in their pages'
  bodies, on every frame: 6% of a `list` frame, 5% of an idle Tables frame. An
  Example fix (load on appear and on navigation), not a framework one.
- **Pictures held whole:** the Tab Views page decodes each mascot it shows in a
  few cells at full size, 2.1 MB apiece (10.5 MB), for as long as it is open.

## Follow-ups

The "noticed" items above, taken up the same day by a second lane.

- **The `list` scenario** (`drive.py`, so `input_latency.py` and `record.sh`
  too). The scenario had not regressed in the framework: the Lists page has
  opened with the focus in its `.searchable` field since that section went to
  the top of the page (2026-07-20; the Edit button in front of it left on
  07-30), and a single-line field takes Down and Up as End and Home, as a
  macOS one does (`TextFieldHandler`, unchanged since February). The scenario
  now Tabs to the fruit list under the field first. Input to frame, p50, 3
  reps: 54.7 ms (the breathing) → 10.2 ms, every one of the 279 inputs
  answered.
- **The file browsers' directory reads.** The List and Tables pages keep the
  rows in `@State`, read by `.onChange(of: browserURL, initial: true)`: once
  when the page opens and once a folder opened. The framework runs that
  spelling once, not per frame, so it was the Example's to fix.
  `FileBrowser.entries(at:)` in the `table` scenario: 6.2% → 0.9% inclusive
  (the one read), `drive.py` CPU 1.30 → 1.05 s.
- **The idle Tables page.** Not the focus breathing: `TUI_FRAME_TRACE` put
  every frame that drew anything at the animated-cells table's 250 ms ticker
  (`state`, about 11 ms each, 0 bytes written: the table opens scrolled out
  of sight), the breathing's own frames being replays at 0.0 ms. The ticker
  now runs only while `onScrollVisibilityChange` says the table is shown.
  Idle, `idle_cpu.py --page tables` over 10 s: 4.1% → 0.1% CPU; scrolled to
  the table, it ticks as before.
- **Pictures held whole** (not changed). Measured on the Tab Views page
  (`drive.py --scenario tabviews`, new): peak RSS 74.8–77.0 MB against
  38.4–38.6 MB on the menu; `footprint` 26 MB, of which `heap` puts 11.0 MB
  in five `[RGBA]` buffers, the mascots at source size (480×569 to
  1024×1024). They are the app's image cache's (64 MiB LRU,
  `TUI_IMAGE_CACHE_SIZE`), which the views' pins share rather than copy, so
  they are bounded by design; no knob reduces them (`imageMaxPixelCount`
  fails a decode, it does not shrink one). Shrinking them is a design with
  costs, left for the owner: a box-sized copy of a file's picture drawn as
  glyphs, filed under the box and the full decode let go, re-decoded on a
  resize (a few ms a picture under the 256 KB synchronous limit, a task
  above it); the terminal-graphics path would need the cell's pixel size,
  and a URL's picture would be fetched again. Seen on the way:
  `TUI_IMAGE_CACHE_SIZE=0` decodes each small file again on every frame
  (peak 207–290 MB, CPU ×3–4 on this page).
- **A deep navigation stack's covered screens** (`b1077deb2`). They are not
  drawn: each frame marks each covered screen's identity active and retains
  its subtree, so its state survives the prune. Measured with new sessions
  `inbox-pushed5` and `inbox-pushed10` (the inbox pushed one a step over
  itself), `ab_bench.py`, 10 reps, against the same tip with that retention
  switched off: `inbox-pushed` −0.3% (indistinguishable), `inbox-pushed5`
  +1.0% (CI +0.0 to +3.4%), `inbox-pushed10` +1.5% (+0.1 to +1.9%), RSS
  +0.3 to +0.6 MB. Well under the 10% that would call for a cheaper
  keep-alive, so none is proposed.

## Second pass, 2026-11-10

Measured on main at `a91f0125b`, the same machine, shared with other lanes
(load 3–33 during the runs; `ab_bench.py`'s CPU time and paired ratios are
what make that usable). Nothing changed in the code: every check below came
back indistinguishable or faster, and the one profile lead was already priced.

**The `.overContent` default (`3bdd2a8d3` … `a14f57331`).** The first of those
four commits, measured alone against its parent the night before, put
`tables-scroll` at +6.7% (CI +5.9 to +9.1%). Measured again on main, against
the same tree with `.besideContent` as the default (a one-line build for the
A/B only), 12 reps:

| scenario | `.besideContent` µs | `.overContent` µs | change | 95% CI |
|---|---|---|---|---|
| tables-scroll | 15.4 | 15.2 | −1.9% | −2.3 … −0.7% |
| table | 8.0 | 8.1 | +1.2% | −0.6 … +2.5% (indistinguishable) |
| megalist | 9.8 | 9.8 | 0.0% | −1.5 … +0.5% (indistinguishable) |
| grids | 45.3 | 42.2 | −6.4% | −9.9 … −5.1% |
| scrollfollow | 435.8 | 387.7 | −11.5% | −13.7 … −10.5% |

The cost is gone. The likeliest reason is `e6169155e`, which came after the
measured commit: a scrolling view now watches the pointer only while it has
an indicator to show, and the eight tables in `tables-scroll` all fit, so
they no longer each register a hover observer and ask for motion reports
every frame. Only the enclosing scroll view does. Not profiled further,
because there is nothing left to remove.

**Regressions since the first pass.** The heaviest scenarios and sessions of
the baseline above, `a98a4b8db` (where that pass started) against
`a91f0125b`, 10 reps:

| scenario | 11-08 µs | 11-10 µs | change | 95% CI |
|---|---|---|---|---|
| gradients | 24,101 | 19,707 | −17.9% | −19.0 … −15.3% |
| app-shapes | 9,794 | 9,600 | −2.5% | −5.5 … −1.8% |
| churn | 8,621 | 8,146 | −5.2% | −6.1 … −4.5% |
| alpharamp | 8,104 | 7,880 | −2.7% | −4.1 … −1.8% |
| texteffects | 7,238 | 6,708 | −7.3% | −9.1 … −3.9% |
| geometry | 4,090 | 3,640 | −11.0% | −11.9 … −9.6% |
| session/notes | 6,135 | 5,685 | −6.8% | −14.0 … +0.8% (indistinguishable) |
| session/settings | 7,384 | 7,117 | −3.7% | −12.3 … −2.5% |
| session/menus | 4,909 | 4,318 | −12.1% | −12.3 … −11.3% |
| session/log | 2,857 | 2,857 | +0.2% | −0.7 … +3.3% (indistinguishable) |
| session/chat | 1,437 | 1,434 | −0.6% | −1.4 … +3.4% (indistinguishable) |

(`picker` and `session/inbox-commands` did not exist at `a98a4b8db`.) No
regressions in time. `session/log`'s resident peak did grow, 36.5 → 44.0 MB
in the A/B and 32.3 → 63.5 MB over 6,400 frames, but it is not held memory:
its caches' entry counts are identical in both builds every 400 steps
(`--cache-sizes`), and `heap` on a 40-second run gives a physical footprint
of 29.0 MB now against 33.2 MB then, peaks 36.8 and 35.1 MB. What grows is
pages the allocator has freed but not yet given back. Left as it is.

**Scroll regions on frames that do not move.** `emit_bench.py`, one binary
with `TUI_SCROLL_OUTPUT=off` against `exact` (the default), ghostty, 8 s
windows, 9 reps: dashboard +2.4% (−8.7 … +4.8%), framedcolumns 0.0%,
kitchensink 0.0% (−3.7 … +16.5%), megalist −2.5% (−4.9 … 0.0%), table 0.0%
(−2.5 … +2.6%). All indistinguishable, and what `Scroll regions for
output.md` said they would be. The tool reads CPU time in centiseconds, so
it cannot resolve anything under a few percent here.

**Profiles, and what was dropped.** `Stress --bench` traced with Time
Profiler (attached by PID) on `gradients` and `session/notes`, read with
`analyze_timeprofile.py --blame`:

- Nothing dominates. On `gradients` the largest of our frames are dictionary
  lookups (5.0% blamed on `__RawDictionaryStorage.find`, spread over the
  animation store, `Color.cachedRamp`, the environment and others),
  `SGRWriter.add` 4.5%, `GradientHalfRows.halfRun` 2.8%.
- `IdentityNode.structurallyEqual`, 2.1% of `gradients` and 4.6% of
  `session/notes`: a lookup whose key is equal to the stored one but built
  this frame walks both chains to the root. A cheaper step (walking without
  reference counting) measured worse on 2026-10-17 (`Optimisations that did
  not pay.md`), which named the lever as fewer walks: identities that share
  nodes across passes. That is a change to how every identity is built, not
  a cheap fix, so it is left for a lane of its own.
- `LocalizedTextSource`'s interner, 1.0% of `gradients`: each
  `Text(LocalizedStringKey)` built in a body hashes its whole key into the
  interner, every frame. Cheaper only by caching on the key's value, a
  design change for a 1% share; left.
