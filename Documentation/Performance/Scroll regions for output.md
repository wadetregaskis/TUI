# Scroll regions for output

Telling the terminal to move a band of rows, rather than rewriting the rows that moved.

**Status: study, and a working prototype off by default (`TUI_SCROLL_OUTPUT`), on a branch. Not landed.**

Measured means run here on 2026-11-01, on macOS 15, with the tools named. Inferred means reasoned from a measurement or
from reading the source, and is marked **[I]**. No timing A/B is reported: the machine was shared throughout, under
loads of 10 to 27, so the costs are given as allocation counts and work done. The terminal CPU figures in section 4 come
from one exclusive slot and are labelled indicative.

## The answer

- **It works, on every terminal measured.** Across 13 `Stress` sessions, 5,200 frames, a full-width band alone sends
  **28.6% fewer bytes**, and a wheel notch over dissimilar rows 89% fewer (4,826 → 507 bytes at 120×40). Every frame's screen
  matches `off`'s in a VT model, and the frames sampled on Apple Terminal, iTerm2, Ghostty and Warp match to the pixel.
- **The narrow scroll view barely matters, which is the surprise.** The worry was that a scroll view narrower than the
  screen would not qualify. On TUI's real pages it nearly always does: of the frames a shift could be found on, 87% on the
  Example's pages and 90% in the sessions qualify at the whole width, since what is beside the view is the same on every row
  (a margin, a border, a blank). DECSLRM margins, on the two hosts that have them, add only 1.4 points. Only a side pane of
  dissimilar text breaks whole rows, and we have no real page of that shape to measure.
- **It costs next to nothing.** Frames that change fewer than 3 rows (61% of those frames) pay one integer comparison.
  A frame that changes more and did not move pays about 9 allocations in a frame of 27,000. Frames that move allocate
  less than before. Nothing is kept between frames.
- **Detecting beats carrying the intent.** A search of every shift over the same frames finds only 2.6% more than the
  planner. So a hint from `ScrollView` or `List` could add at most that, at the price of a `FrameBuffer` field and a
  new way for a memo to serve a stale fact. Nothing to choose there.
- **My recommendation: on by default at `exact`, once it has soaked**, with `TUI_SCROLL_OUTPUT=off` as the way out, and
  no public setting. It has no noticeable trade-off, so I would not make it a setting in the API.
- **A bigger finding on the way: under tmux, TUI's hold makes every frame repaint the whole pane at the client.** A
  one-cell change costs 6,198 bytes against 38. Example idling under tmux sends 153 KB/s where it should send 2 KB/s.
  That is 70 to 260 times, it dwarfs anything here, and fixing it looks like one line. See section 3.

## 1. How output works now

`RenderLoop` renders the frame to a `FrameBuffer`, and `FrameDiffWriter.buildReusingOutputLines` builds a terminal-ready
string per row: background, `ESC[2K`, the row's content clipped and compensated for the host, padding, reset. A row whose
raw line and parameters are unchanged reuses last frame's string, so a built row costs nothing to keep.

`writeContentDiff` then writes the difference, in two levels:

1. **Per row.** `computeChangedRows` compares each new string with what is on screen. String equality with a pointer
   fast path, so a frame that changes nothing costs about as many comparisons as it has rows.
2. **Per cell.** For a changed row, `ANSIRowCells` takes both rows apart into (scalar, netted SGR) per column and writes
   the spans that differ, bridging gaps of up to 8 cells (`Intra-line output diffing.md`). A row that does not decompose
   (a wide glyph, a compensation escape, a hyperlink) is rewritten whole, which re-anchors it.

There are no line hashes in the writer; "line hash" in the brief is string equality here. A row's decomposition is kept
for the next frame (`CellCache`), checked against its string, so nothing that writes behind the cache can make it stale.

The frame is one `write()`, held by mode 2026 where the host implements it (`Terminal.beginSynchronizedUpdate`): the begin
marker goes in after any image transmissions, and survives only if the frame moves the cursor to a row.

Nothing moves rows. `CSI r` is sent only at startup, as a default put back (`Terminal.inheritedDefaults`), and the survey
said so: "no frame scrolls today". So a list that scrolls by one row rewrites every row it shows, each at the cost of
its differing cells. Rows that look alike cost a few bytes each. Rows that do not, cost the whole row:

| One wheel notch, 3 rows | Bytes | Source |
|---|---:|---|
| TUI, rows that look alike | 749 | Q14 (b) |
| SwiftTUI, rows that look alike | 132 | Q14 (b) |
| TUI, dissimilar rows | 10,200 | Q14 (b) |
| SwiftTUI, dissimilar rows | 290 | Q14 (b) |

## 2. The approaches

### (a) Detect the shift in the writer

Compare the new frame with what is on screen and find *k* where new row *i* equals old row *i + k*.

**Finding the band (what the prototype does).** `ScrollPlanner`, in `Sources/TUIApp/Rendering/ScrollPlanner.swift`:

1. **The gate.** Fewer than 3 changed rows cannot pay for a region's bytes. One comparison, and most frames stop here.
2. **Vote on whole rows.** Hash the changed rows, old and new. Each new row whose hash names at most two old rows votes
   for the distance between them. Rows naming more say nothing: blank rows and ruled lines match everywhere.
3. **Vote on columns, if whole rows did not settle it.** Count, per column, how many rows changed there. The columns most
   rows changed in are the moving rectangle. Hash the *text* in those columns (not the styling, so a row whose highlight
   moved still says where it came from) and vote again. This is what sees a list beside a side pane.
4. **Price it.** For each shift found, for each row, what the cell diff would write where it is, against what it would
   write over the moved screen, from a cell walk that builds no strings. The band is the contiguous run of rows that gains
   most (Kadane). The rows it exposes are charged. It must save at least 40 bytes and a tenth of the frame.
5. **Do it, and carry on.** Send the region and the scroll inside the frame's hold, tell the writer's picture of the
   screen that the rows moved (`previousLines` and `CellCache`), and let the ordinary diff run against that picture.

That last step is why content changing at the same time needs no special code. A highlight that moved with the rows, a
scroll bar's thumb, a fixed header and a row edited in the same frame are all just cells that differ from the moved
screen, and the diff repairs them. Nothing is special-cased, and the arithmetic of the diff, which is well tested, stays
the only thing that decides what is written.

| | Whole rows (`exact`) | Columns too (`residue`, `margins`) |
|---|---|---|
| A focus highlight moving with the rows | repaired on the moved screen | same |
| Scroll bar on the same rows | its rows repaired; the track is alike on all | same |
| Fixed header, footer | outside the band; Kadane stops at them | same |
| A side pane of dissimilar text | no row matches: **no scroll** | `residue` moves the width and repairs the pane; `margins` moves only the rectangle |
| A row changing per frame (a process table's numbers) | fewer votes, usually still enough | column vote and price sort it out |
| Rows moved by something that is not scrolling (a row removed above, a log's tail, a chat bubble) | found | found |

**Cost on frames that are not scrolls.** Measured in section 4: nothing kept, about 9 allocations on a frame that changed
3 or more rows, and hashing those rows' strings, which the row diff is about to take apart anyway at much greater cost.
`newCells` carries the planner's decompositions on to the diff, so no row is taken apart twice.

**What can go wrong.** A false shift cannot corrupt the screen: the diff repairs against the moved model, so a bad shift
costs bytes and not correctness. The model being wrong about the terminal can corrupt it, and that is section 3's job.
What is left is a plan that loses a little: 153 of 5,200 frames cost more than `off`, by 1,954 bytes in all against
1,263,288 saved.

### (b) Carry the intent from the pipeline

`ScrollView` (`handler.scrollOffset`, `_ScrollViewCore`), `List` and `Table` (`ItemListHandler`, `ScrollRowWindow`) know
they moved, by how much, and over which rectangle. A `FrameBuffer` field could carry that to the writer, composited as
`hitTestRegions` is.

- **Band:** given. **Content changing at once:** the same repair as (a), since the intent says nothing of which cells
  changed.
- **Cost on frames that are not scrolls:** a field on `FrameBuffer`, which is everywhere. `hitTestRegions`, the nearest
  precedent, appears 213 times in 96 files, every one a place a rectangle can be translated, clipped or lost. The memory
  note on `RenderContext` fields found an `Int` there costs 2.4%; `FrameBuffer` is not that hot, but this is not free
  **[I]**.
- **What goes wrong:**
  - *A memo.* A served subtree's buffer carries the hint it was built with. A hint is a fact about a frame, not a function
    of the view, so a value memo would keep it and serve it. Clearing it means walking what memos return. This is the
    side-effect class the memo verifier is blind to (`memo-verifier-blind-to-side-effects`).
  - *Composition.* A band under an overlay, a sheet's veil, a translucent layer, a clip. The writer sees only the result.
  - *It cannot see a move that is not a scroll.* By the sessions' action names, about a quarter of all bytes saved (320,000 of
    1.33 million) are on frames where rows arrived, left, were sorted, dragged or inserted, with no offset moved **[I, my
    reading of the names]**.
  - *It must be verified anyway*, since an offset that moved does not promise the rows did: animated content, a row whose
    height changed. Verifying is detecting.

### (c) Hybrids

- **A hint that narrows the detector.** Pointless here: the detector only runs on frames where 3 or more rows changed,
  and on them it costs a fraction of the diff it precedes. There is nothing to narrow.
- **A detector that verifies a hint.** Worth having only if the hint finds something the detector cannot. It does not:

| Session, 150 steps | Frames searched | Search finds | Planner plans | Planner missed | Search saves | Planner saves |
|---|---:|---:|---:|---:|---:|---:|
| inbox | 32 | 17 | 21 | 0 | 18,450 | 24,774 |
| log | 96 | 74 | 61 | 15 | 158,225 | 158,237 |
| chat | 30 | 22 | 21 | 2 | 27,242 | 23,791 |
| playlist | 48 | 27 | 42 | 2 | 25,645 | 40,877 |
| processes | 133 | 29 | 28 | 4 | 44,337 | 45,933 |
| editor | 9 | 8 | 7 | 1 | 16,249 | 15,691 |

Measured by `scroll_output.py oracle`, which replays the frames through the VT model and tries every shift up to 12 rows,
the best columns for it, and the best rows in those, priced by one cost function for both. An oracle's *search* can
under-report (it stops at 12 rows and at one rectangle per shift), which is why the planner sometimes beats it. **The
frames the planner missed and the search found would have saved 7,591 bytes of 290,148: 2.6%.** No hint could add more
than that, since a hint could only tell the writer what the search found [I].

- **The hybrid that does pay, and which the prototype is: two cheap looks.** Whole rows first, which settles most frames
  and needs no cell walk to find the shift, then columns only if that did not settle it. Both shifts are priced when the looks disagree: a
  table with churning numbers gives whole rows few votes and columns many, and only the price knows which moved.

**One thing a hint would give that detection does not:** it could skip the hashing of 3 or more rows on frames with
no scroll at all. Those frames are about 26% of the sessions' frames, and it would save those 9 allocations. Not worth a
field on `FrameBuffer`.

### Measured on real frames

`scroll_output.py sessions`, 120×40, host Ghostty, 400 steps each. A session is the real render loop, playing the same
script at every level, so the frames line up. "Looked at" is frames that changed 3 or more rows. "Moved" is frames that
wrote fewer bytes than `off`.

| Session | Frames | Looked at | Moved, `exact` | Moved, `margins` | `off` bytes | `exact` | `residue` | `margins` |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| inbox | 400 | 93 | 65 | 65 | 201,896 | -48.9% | -48.9% | -48.9% |
| log | 400 | 272 | 143 | 153 | 1,041,760 | -51.5% | -51.5% | -52.5% |
| chat | 400 | 107 | 48 | 64 | 344,270 | -28.4% | -29.0% | -31.9% |
| editor | 400 | 37 | 22 | 25 | 113,310 | -50.8% | -51.8% | -53.8% |
| notes | 400 | 113 | 21 | 25 | 468,112 | -5.9% | -5.9% | -6.9% |
| settings | 400 | 72 | 22 | 22 | 184,946 | -23.5% | -23.5% | -23.5% |
| playlist | 400 | 132 | 103 | 116 | 289,122 | -40.5% | -41.0% | -42.5% |
| jobs | 400 | 192 | 29 | 29 | 217,084 | -28.1% | -28.1% | -28.1% |
| processes | 400 | 363 | 80 | 92 | 581,862 | -30.1% | -30.6% | -33.2% |
| menus | 400 | 229 | 10 | 12 | 170,410 | -3.7% | -3.8% | -4.4% |
| themes | 400 | 107 | 0 | 0 | 420,696 | 0.0% | 0.0% | 0.0% |
| glides | 400 | 137 | 35 | 38 | 51,624 | -22.3% | -22.8% | -23.0% |
| inbox-docked | 400 | 183 | 33 | 37 | 328,373 | -9.4% | -9.4% | -11.4% |
| **All** | **5,200** | **2,037 (39%)** | **611 (12%)** | **678 (13%)** | **4,413,465** | **-28.6%** | **-28.8%** | **-30.0%** |

These scripts act on every step, so a real app, which mostly sits still, moves on a smaller share of its frames; what
carries over is the share of the *bytes*, since the bytes are spent on these frames. At 200×50 (four sessions) the
saving is larger, -47% to -55% on `log` and `inbox`, since a row is longer and its text is what is saved. On Apple
Terminal the host holds a level at `exact` and the figures match `exact`'s here. Rows of similar text gain little: the
`themes` session never scrolls, and `menus` is short lists.

Where the bytes go, per step of the same kind (`off`, then `margins`): `log` a line arriving at the end it follows, 3,091 →
288; `editor` a newline, 3,184 → 428; `settings` a sync that adds a row, 1,238 → 178; `chat` a message arriving, 3,289 → 1,264;
`inbox` a selection that scrolls, 1,182 → 485; `processes` a page, 3,903 → 2,591. A newline and a sync are not scrolls by any
scroll view's account, and (b) would see neither **[I]**.

`Stress` autopilot, through a PTY (`emit_bench.py --bytes`, 3 s windows): `scrollfollow` 25,887 → 11,670 bytes a second.
`scrolleager`, `megalist`, `table`, `kitchensink`, `dashboard` and `framedcolumns` do not move rows, and show no change in
bytes (±2%), as they should. Its CPU column is not reported, as agreed: the box was busy.

### The Example's pages

`scroll_output.py pages`, 120×40. Each page once: 20 Down, 10 Up, 4 PgDn, 4 PgUp, 12 wheel down, 12 up. These come from one
run at `off` and the census, which prices each level on the same frames, because a live page's timing makes two runs
incomparable. Prices run a little under what is really saved (`log`: priced 347,793, measured 411,496).

| Page | Looked at | `off` bytes | Moved, `exact` | Saved | Moved, `margins` | Saved | Band width |
|---|---:|---:|---:|---:|---:|---:|---:|
| Text | 95 | 109,910 | 24 | 40% | 40 | 41% | 120 |
| Colors | 71 | 444,571 | 50 | 62% | 52 | 65% | 120 |
| Containers | 50 | 141,078 | 33 | 69% | 33 | 69% | 120 |
| Overlays | 37 | 53,024 | 11 | 49% | 12 | 54% | 120 |
| Layout | 67 | 40,919 | 5 | 29% | 6 | 31% | 120 |
| Buttons | 37 | 156,371 | 5 | 5% | 11 | 10% | 118 |
| Toggles | 29 | 135,065 | 25 | 43% | 25 | 43% | 120 |
| Text input | 32 | 101,684 | 26 | 56% | 26 | 56% | 120 |
| Radio | 2 | 1,421 | 0 | 0% | 0 | 0% | — |
| Spinners | 266 | 222,090 | 2 | 2% | 2 | 2% | 120 |
| Lists | 26 | 152,795 | 24 | 64% | 24 | 64% | 120 |
| Tables | 27 | 91,778 | 12 | 49% | 12 | 49% | 120 |
| Scroll views | 109 | 30,148 | 22 | 4% | 54 | 24% | 31 |
| Sliders | 64 | 101,881 | 4 | 16% | 4 | 16% | 120 |
| Steppers | 26 | 16,741 | 7 | 37% | 8 | 44% | 120 |
| Split views | 14 | 37,447 | 12 | 41% | 12 | 41% | 120 |
| Images | 2 | 1,605 | 0 | 0% | 0 | 0% | — |
| Emoji | 5 | 23,274 | 0 | 0% | 0 | 0% | — |
| Pickers | 5 | 10,468 | 3 | 43% | 3 | 46% | 120 |
| Progress | 375 | 502,959 | 9 | 7% | 9 | 7% | 120 |
| Mouse | 53 | 155,788 | 24 | 49% | 25 | 50% | 120 |
| Theme | 26 | 55,722 | 24 | 40% | 24 | 40% | 120 |
| Empty state | 2 | 1,544 | 0 | 0% | 0 | 0% | — |
| Tab views | 30 | 105,738 | 25 | 54% | 25 | 55% | 120 |
| Forms | 30 | 137,112 | 26 | 65% | 26 | 65% | 120 |
| Persistence | 16 | 39,235 | 10 | 48% | 10 | 48% | 120 |
| Lifecycle | 5 | 2,420 | 0 | 0% | 0 | 0% | — |
| Preferences | 2 | 1,772 | 0 | 0% | 0 | 0% | — |
| Focus | 18 | 41,868 | 13 | 53% | 14 | 54% | 120 |
| **All 29** | **1,521** | **2,916,428** | **396** | **37.4%** | **457** | **38.6%** | |

Band width is the median of what the plans used, full width unless a narrower one priced better. A page that shows little
movement here (Radio, Images, Empty state, Preferences) has no scrolling content at 120×40. Spinners and Progress change many
rows by themselves, and pay for being looked at, which is what the allocation table prices.

**So what fraction of real layouts qualify? Nearly all of them.** Of the frames a shift could be found on: **87% on the
Example's pages (396 of 457) and 90% in the sessions (600 of 669) qualify at the whole width**, and those carry 97% of the
saving on the pages (37.4 of 38.6 points) and 95% in the sessions (28.6 of 30.0). The brief's worry was that a scroll view is
usually narrower than the screen, and it is, but what is beside it is the same on every row: a page margin, a box's two
walls, a blank, a scroll bar's track. A row's equality does not care how wide the scroll view is, only whether the rest of
the row matches. The exception is the Scroll Views page: boxes of 8 rows of short text with a scroll bar in each, so little is at
stake and a moved row drags scroll-bar cells that need repair: 4% at the whole width, 24% with margins, of 30 KB. On a 200-column
screen the exception holds and the rest grows
(`-` Lists 71%, `=` Tables 54%, `m` Mouse 55%).

This was measured on what we have, and what we have is short of **one shape: a list beside a side pane of dissimilar
text**, a mail client's. Only the fixture in section 4 prices that. Whole rows do not qualify there at all.

## 3. Terminal mechanics

`Tools/TerminalProbes/scroll_region_probe.py` paints a grid of colours, does one operation, captures the screen, and
classifies every cell against each hypothesis. Records in `Tools/TerminalProbes/data/*-scroll.json`; the table belongs to the
survey (`Terminal compatibility survey.md`, "Moving a band of rows"), and this is its summary.

| | Apple Terminal 455.1 | iTerm2 3.7.6 | Ghostty 1.4.0 | Warp v0.2026.10.21 |
|---|---|---|---|---|
| `CSI t;b r` + SU, SD | as told | as told | as told | as told |
| IL, DL at the region's top | as told | as told | as told | as told |
| IND, RI at the margins | as told | as told | as told | as told |
| Exposed rows | pen's background | pen's background | pen's background | pen's background |
| Cursor after `CSI r` | home | home | home | home |
| DECSLRM (`?69h`, `CSI l;r s`) | **ignored: the whole width moves** | as told | as told | **ignored: the whole width moves** |
| DECRQM `?69` | not asked: it prints | 2 (reset) | 2 (reset) | no reply |
| DECCRA | ignored, nothing printed | **destination row and column swapped** | ignored | ignored |
| Kitty classic placement in a band | — | **stays** | **moves with the band** | stays |
| Kitty Unicode placeholder in a band | — | moves | moves | not measured |
| Row store after a scroll over emoji | travels with the row | travels | travels | travels |

kitty 0.49.1 cannot open a window on this VM (no OpenGL 3.3), so it is unmeasured, and xterm, WezTerm and foot are not
installed. From memory, unchecked here: xterm and WezTerm have DECSLRM, and kitty, foot, GNOME Terminal and Alacritty do not
**[I]**. The prototype gives none of them `margins`, so nothing rests on that.

**DECSLRM is a hazard and not merely an absence.** Where it is ignored, `CSI 11;70 s` is a cursor save, harmless, but the
scroll then moves *the whole width*, and the writer's picture is wrong in exactly the columns it thought it left alone. It
cannot be sent on a guess, and asking (DECRQM) is the shape Apple Terminal prints. So `margins` is by named host only, and
only those measured. An unknown terminal, or a wrong identity over ssh, gets `exact`, which any VT100 does correctly.

**Why not the others.**

- **`CSI L`, `CSI M` (IL, DL):** identical to SU and SD on all four, and they need a cursor move. No reason to prefer them.
- **DECCRA:** a rectangle is what we want, and three of four hosts cannot do it: two ignore it and iTerm2 3.7.6 swaps the
  destination's row and column, measured with no other reading fitting (0 wrong cells of 2,000). It needs a guard per host
  and helps nobody DECSLRM does not.
- **IND and RI:** correct everywhere, one row per operation. A fallback nobody needs: SU and SD work on all four.

### Hazards, one by one

- **Kitty images and placeholders in the band.** Placeholders are text, so they ride, measured on Ghostty and iTerm2. A
  *classic placement* (TUI's hairlines and pictures under text: `HairlineLayer`, `PictureUnderTextLayer`) moves on Ghostty
  and stays on iTerm2. The layers keep a model of what the terminal holds, so a move behind their back breaks it in a
  host-dependent way. So the prototype will not move anything while a frame on screen or the new one carries a mark. A page
  with `.hairline` separators therefore does not scroll in hardware. Telling the layers would lift that; not done.
- **Rows that carry more than cells.** A hyperlink's OSC 8 or an image's payload: `rowMayRide` refuses them. Not measured
  whether a link moves correctly; refused rather than assumed.
- **Apple Terminal's quirks.** It keeps three facts per row (`dsr-lies-paint-is-truth`). A marker written after a scroll over
  a treated VS-16 row and a treated flag row lands in the column it does with no scroll, so the row store travels with
  the row [measured, two classes]. `repaintRightEdge` works by rows *written*, though, so a row it would repair is
  refused on Apple Terminal (`containsTerminalAppCursorAdvanceQuirk`).
- **tmux.** See below.
- **Cursor after region changes.** `CSI r` homes it, on all four. The writer marks the frame as having moved the cursor, so
  `parkCursor` puts it back, and every later write begins with an absolute move. Origin mode is off (`inheritedDefaults`).
- **A region left set on a crash.** A frame sets and releases the region in one write, so only a signal or a failed write
  between them can leave one. `Terminal.outputModesOff` now also owes `ESC 7`, `CSI r`, `CSI ?69 l`, `ESC 8` when scrolling
  is on, and `FatalSignalTerminalRestore` pays that debt. Measured on a real process by sending the signals: SIGSEGV,
  SIGQUIT and SIGTERM each write it, and with scrolling off nothing changes. The save and restore are so that a crash's
  report is not written over the top row.
- **A frame not held, where 2026 is missing.** Apple Terminal does not implement it (hypothesis, in the survey). There a
  scroll and its repair can paint apart, showing a blank exposed row for a paint. Exposed rows are in the page's background,
  so the flash is the page's colour, and today's rewrite tears there as well (`ESC[2K`, then the row). What must not be
  seen is a fixed column moving and coming back, so a host without a hold stops at `exact`, which moves only rows that truly
  moved. On hosts with a hold (iTerm2, Ghostty and Warp all answer `?2026` with 2), the whole frame is shown at once.
- **Ghosting.** I looked for it the only way it can be looked for without eyes on it: the pixel differential below, on
  real frames. None was found at 7 stops per session per host, and any cell left behind would have shown. A one-frame
  flash during a scroll cannot be seen this way. So far nobody has looked at this running live. **That is the owner's to
  check, once, on Apple Terminal.**
- **Not on the alternate screen.** A full-screen region's scroll on the primary screen may push rows to scrollback on some
  hosts **[I]**. TUI draws on the alternate screen, so this does not arise today.
- **Selection in the terminal.** Moving cells should carry a native selection with them, where rewriting would not. Not
  measured. No harm is expected **[I]**.

### tmux, and the finding that outranks this study

`Tools/TerminalProbes/tmux_scroll_probe.py` plays the terminal on a pty, so it counts what tmux 3.7c sends **its client**,
which is what travels over ssh. Dissimilar rows, 120×40 window, 3 rows a notch:

| Pane | App sends | Held by the app (`?2026`), as TUI does | Not held |
|---|---|---:|---:|
| Whole window | whole rows | 6,225 B | 5,091 B |
| | region + exposed rows | 6,195 B | **472 B** |
| | **one cell** | **6,198 B** | **38 B** |
| Above another (full width) | whole rows | 3,074 B | 2,536 B |
| | region + exposed rows | 3,056 B | **504 B** |
| | one cell | 3,062 B | 69 B |
| Beside another (not full width) | whole rows | 3,907 B | 2,731 B |
| | region + exposed rows | 3,891 B | 3,891 B |
| | one cell | 3,897 B | 73 B |

Means over 12 notches. A window of 40 sometimes holds one stray whole-pane redraw from tmux, about 6 KB, and otherwise
agrees: 191 B for the cell, 625 for the region, 5,245 for whole rows, in the record `data/tmux-3.7c-scroll.json`.

**Read the "one cell" rows.** tmux accepts a pane's hold and, at its end, repaints the whole pane at the client: it does
not forward the hold, and it drops what it knew of what changed. TUI wraps every frame that writes a row in a hold, on
every host (`Terminal.beginSynchronizedUpdate`), so **under tmux every frame is a full repaint.** The real thing, Example
on the Lists page in a tmux pane:

| | Idle, bytes a second | Each Down key |
|---|---:|---:|
| As shipped | **152,292 to 153,192** | **10,356 to 11,332** |
| `TUI_SYNCHRONIZED_OUTPUT=0` | 2,148 to 2,154 | 39 to 43 |

Which says, for this study, that:

- Under tmux with holds on, a region gains nothing and loses nothing, and the prototype does not bother
  (`ScrollOutput.level`).
- With holds off, tmux does the right thing: 472 bytes a notch in a full-width pane (it re-emits `CSI r`, `CSI n S`, against
  5,091). Beside another pane, without margins in the client's terminfo, it redraws the region itself, which is worse than
  rewriting (3,891 against 2,731), and the writer's price cannot see that. Which sort of pane it is in, it cannot know.

And for TUI, whatever comes of this study: **stop sending the hold under tmux** (done 2026-11-01, not yet soaked over ssh). That is the survey's open question
("unknown whether a pane's hold reaches the client"), answered. What is lost is tmux's own guard against showing a pane
half-drawn, between two reads of the app's frame, which is one `write()`. I would take that. tmux does not hold its client in
these runs either way (no `?2026` reached the client, `TERM=xterm-256color`). It needs a soak over a real ssh link, by
eye, before it lands.

## 4. What it is worth

**Bytes a notch** (the fixture in `ScrollOutputTests`, 120×40, dissimilar rows, one notch of 3 rows):

| Rows | `off` | `exact` | `residue` | `margins` |
|---|---:|---:|---:|---:|
| Dissimilar, full width | 4,826 | **507** | 507 | 507 |
| Dissimilar, beside a 20-column side pane | 4,066 | 4,066 | 1,437 | **385** |
| Rows alike (`Row 1234 some text…`) | 317 | 317 | 317 | 317 |

The first is the 89% that SwiftTUI's trick is known for. The third is the case where it rightly does nothing: the cell diff has
already got it, and the price sees that. The second is where the levels differ.

**Bytes per second.** At 30 notches a second on dissimilar rows at 120×40, 145 KB/s (1.2 Mbit/s) becomes 15 KB/s (0.12 Mbit/s).
Q14's rows of 190 random letters, on a wider screen, scale that up to 2.4 Mbit/s [I].

**A held key, a trackpad, a slow link.** A held Down on a `List` is the 1-row case, once the focus reaches the edge: each frame
moves every row a row, and costs one exposed row, not all of them. At 120×40 on the same rows, that is about 170 bytes
against about 4,800 **[I, from the table]**; at 80×24 on a real terminal's stream, 145 against 2,215 (measured, below). A trackpad sends many notches, and `FramePacer` caps the frames, so what it costs follows the pacer, not
the fingers. Each paced frame is a bigger shift, which costs more exposed rows but no more than the rows it would have
rewritten. On 1 Mbit/s the difference is a scroll that keeps up against one that does not **[I]**; nobody has sat on a slow link
and watched.

**In the app.** Allocation counts over a whole session, `Stress` release build, 300 steps, by `Tools/Profiling/AllocCount`:

| Session | `off` | `exact` | `residue` | `margins` | What it is |
|---|---:|---:|---:|---:|---|
| log | 2,017,394 | 1,971,449 (-2.3%) | 1,972,279 | 1,971,842 | moves often: fewer spans built |
| inbox | 1,873,993 | 1,868,966 (-0.3%) | 1,869,202 | 1,869,291 | moves some |
| jobs | 1,967,084 | 1,967,106 (0.0%) | 1,969,829 | 1,970,190 | moves rarely |
| settings | 4,071,972 | 4,075,844 (+0.1%) | 4,081,251 | 4,081,412 | moves rarely |
| themes | 8,108,349 | 8,109,107 (0.0%) | 8,116,082 (+0.1%) | 8,116,257 | never moves: the cost alone |
| processes | 1,312,096 | 1,321,460 (+0.7%) | 1,337,245 (+1.9%) | 1,335,937 | changes many rows on every frame |

Repeated, three of them agree to within 8 allocations, so these differences are real. `themes` is the honest measure of what it
costs where it never pays: 87 frames looked at, 9 allocations each at `exact`,
89 at `residue`, in a run allocating 27,000 a frame. `processes` is the worst case I can find: 34 per looked-at frame at
`exact`. **Frames changing fewer than 3 rows (61% in these scripts, far more in a real app): one integer comparison, and no
allocation.** Off, there is that and a stored byte. Memory kept between frames: nothing but two flags and an optional
reference; the planner's arrays go when the frame does. CPU: none measured, by agreement, as the box is shared.

**In the terminal.** A local terminal may repaint faster when told to scroll, or it may not. Each host fed the same notches
two ways (`scroll_region_probe.py drive --cpu`, its own CPU time, 3 reps, under one exclusive slot, indicative only):

| Host, size | Workload | Whole rows, B/notch | Region, B/notch | Whole rows, CPU s | Region, CPU s | Idle, CPU s |
|---|---|---:|---:|---:|---:|---:|
| Apple Terminal 80×24 | wheel, 3 rows at 30/s | 2,215 | 327 | 0.36 | 0.32 | 0.03 |
| | held key, 1 row at 30/s | 2,215 | 145 | 0.35 | 0.31 | 0.03 |
| | smooth, 1 row at 120/s | 2,215 | 145 | 0.31 | 0.25 | 0.01 |
| iTerm2 80×25 | wheel | 2,306 | 327 | 1.38 | 1.39 | 0.15 |
| | held key | 2,306 | 145 | 1.41 | 1.40 | 0.15 |
| | smooth | 2,306 | 145 | 1.31 | 1.27 | 0.12 |
| Ghostty 56×19 | wheel | 1,304 | 255 | 0.28 | 0.30 | 0.02 |
| | held key | 1,304 | 121 | 0.28 | 0.31 | 0.02 |
| | smooth | 1,304 | 121 | 0.27 | 0.23 | 0.01 |
| Warp 124×47 | wheel | 6,376 | 459 | 1.57 | 1.48 | 0.09 |
| | held key | 6,376 | 189 | 1.59 | 1.47 | 0.07 |
| | smooth | 6,376 | 189 | 1.05 | 0.90 | 0.06 |

CPU seconds over 10 s (smooth: 5 s), median of 3, from `ps` at centisecond resolution, on what the OS reports as the
terminal's CPU, on a machine at load 2 to 4. Ghostty's includes an instance the owner had open, idle. What this says:
**a terminal does not repaint meaningfully faster for being told to scroll.** Apple Terminal spends 11 to 19% less, Warp 6 to 14%
less, iTerm2 nothing, Ghostty anywhere from +10% to -15% on a very small window. What it spends goes on drawing, which a
moved row costs as much as a written one, not on parsing. Time to get through a notch (`CSI 5n` round trip, unpaced, p50) is
0.14 → 0.08 ms on Apple Terminal, 0.28 → 0.06 on Warp, 0.10 → 0.06 on Ghostty, and on iTerm2 about 21 ms either way, which is its
reply path and not its parser **[I]**.

**So is this mostly for slow links?** Yes. Locally it is harmless and a little cheaper for the terminal. Where each byte has to
travel it is a tenfold improvement on what a scroll costs, and scrolling is the expensive thing an app does. Over ssh to tmux
it needs the tmux fix first.

## 5. Recommendation

**Land approach (a), the hybrid of two looks, at `exact`, on by default after a soak.** No public API, and no setting beyond
the environment switch, which stays as the way out as `TUI_SYNCHRONIZED_OUTPUT` is.

- **Cost:** none noticeable. Figures above.
- **Whether it needs a setting:** no. I looked for a use case where one would want it off and found none but a terminal
  that gets it wrong, which is what the environment switch is for. What could still make me wrong is in "Not verified" below.
- **Default per host:** `exact` for Apple Terminal, iTerm2, Ghostty, Warp and an unidentified terminal. Off under tmux with
  holds on, which by the other recommendation goes away, and then `exact`.
- **`residue` and `margins`:** I would leave these out of the first landing. Measured, `exact` gets 28.6% of the bytes, `residue`
  0.2 more, `margins` 1.4 more, and `margins` is the only part with a real hazard. Keep the code on the branch, or delete it,
  your call. A side-pane app is where they would earn their keep, and that case is measured only on a fixture so far:
  4,066 → 385 bytes a notch with margins, 1,437 without. If your apps look like that, keep them.

**For you to decide:**

1. **Default on, or a soak with it off?** I recommend on, after you have watched one scroll on Apple Terminal and on tmux.
2. **`margins` and `residue`: keep or drop?** I would drop them for now.
3. **Stop holding under tmux**, separately and first? Done 2026-11-01 (`TUI_SYNCHRONIZED_OUTPUT=1` asks for it anyway). A soak over
   ssh is still to come.
4. **Hairlines.** A page with `.hairline` list separators does not scroll in hardware at all, in the prototype. Making
   `HairlineLayer` follow a band is a known piece of work, if you use them often enough to care.

## The prototype

`TUI_SCROLL_OUTPUT` = `off` (default), `exact`, `residue` or `margins`, read once. A level is the most a host may get:
`ScrollOutput.level(_:on:holds:)`.

- `Sources/TUIApp/Rendering/ScrollPlanner.swift`: the switch, the plan, the planner, the census.
- `FrameDiffWriter.movingBand`: asks, emits, and moves its picture of the screen. Everything after it is the existing diff.
- `ANSIRowCells`: comparing with a row somewhere else, and `forEachDifference`, shared with the diff.
- `Terminal.scrollRegionReset`: the debt, when scrolling is on.
- `TUI_SCROLL_CENSUS=-` or a path: what each level would have done with each frame.
- `TUI_HEADLESS_STREAM=path`: every byte a `HeadlessApp` is sent, so a session's output can be played elsewhere.

**How it was verified: paint is the truth.**

- **VT model, in Swift** (`Tests/TUIAppTests/ScrollOutputTests.swift`, `VTScreenModel`): each frame's screen against a whole
  repaint of it, at all levels, on four hosts' models, over 16 layouts of random scrolls, edits and selections, and no region
  left set afterwards. 15 tests.
- **VT model, independently, in Python** (`scroll_output.py sessions`): every step of every session at every level, against
  `off`'s screen at that step, on what each cell paints. 5,200 frames × 3 levels at 120×40, four more sessions at 200×50, five on
  Apple Terminal's model. **No differences.**
- **Real pixels** (`scroll_region_probe.py drive --replay`): the same frames reached two ways, `off` and scrolling, on the
  terminal itself, in held updates as `Terminal.endFrame` sends them, and captured at 7 stops per session, on the steps that
  moved. Four sessions, `log`, `inbox`, `chat`, `processes`: Apple Terminal 455.1 at `exact` (80×24), iTerm2 3.7.6 at `margins` (80×25),
Ghostty 1.4.0 at `margins` (56×19), Warp v0.2026.10.21 at `residue` (124×47). **No pixel differs on any host.** A consent dialog
("Stress" would like to access your Documents folder; I could not establish whose run raised it, and did not answer it) sat over
part of the iTerm2 and Warp windows during those runs, the same in both pictures. Each stop was checked to have changed from the last, by 60,000
  to 330,000 pixels, so these are not one still picture.
- **The suite**, off by default: 14,166 tests pass. With `TUI_SCROLL_OUTPUT=margins` and `TERM_PROGRAM=ghostty` set over the
  whole suite, only three more fail than with it off under that host: two pin the bytes of the debt, which has grown by what
  it should, and one (`StatusBarFrameDiffTests`) keeps a little screen model of its own that does not know regions, which a tooltip
  moving the bar's top edge now uses.

**Not verified.** A real app under a real hold, live, by eye: the replay is the same bytes, but nobody has watched a scroll.
Linux terminals. Hairlines under a move, because they are refused. Anything at a resize, where the writer invalidates and so
does nothing.

## Reproducing

```sh
swift build -c release --product Stress && swift build -c release --product Example   # one --product at a time
Tools/Profiling/scroll_output.py sessions --stress .build/release/Stress --out s.json
Tools/Profiling/scroll_output.py pages --example .build/release/Example
Tools/Profiling/scroll_output.py oracle --stress .build/release/Stress
clang -dynamiclib -O2 -o /tmp/alloc_count.dylib Tools/Profiling/AllocCount/alloc_count.c
Tools/Profiling/scroll_output.py allocs --stress .build/release/Stress --dylib /tmp/alloc_count.dylib
Tools/Profiling/emit_bench.py Stress Stress --env-new TUI_SCROLL_OUTPUT=margins --bytes --scenarios scrollfollow
Tools/TerminalProbes/scroll_region_probe.py drive --terminal ghostty --scratch /tmp/s --out out.json
Tools/TerminalProbes/scroll_region_probe.py drive --terminal ghostty --scratch /tmp/s --replay --stress Stress --level margins
Tools/TerminalProbes/scroll_region_probe.py drive --terminal ghostty --scratch /tmp/s --cpu
Tools/TerminalProbes/tmux_scroll_probe.py --app .build/release/Example --page -
```
