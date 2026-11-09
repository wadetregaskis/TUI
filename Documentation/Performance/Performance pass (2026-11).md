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
