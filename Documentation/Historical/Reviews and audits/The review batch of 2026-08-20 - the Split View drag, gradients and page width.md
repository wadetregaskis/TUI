# The review batch of 2026-08-20 - the Split View drag, gradients and page width

*The owner's list of review items from 2026-08-20 and the four passes that worked through it over two
days: Example pages, disclosure, hover, borders, a sluggish Split View drag, 256-colour gradient
banding, mono images, and how much of the terminal's width each page uses. Ids: none (the log names
two questions Q1 and Q2, both answered). This is the readable story;
[the full log](<../../Reviews/Review batch, 2026-08-20.md>) stays in place with the measured tables and the reasoning in full.*

## In short

About twenty-five commits landed across four passes. Most items were small and shipped in the first
pass. Three took real work. The Split View drag was slow because writes block and a drag frame was
mostly redundant bytes: collapsing restated SGR, emitting SGR as deltas and diffing within a line
took a 140x42 drag frame from 10,620 bytes to 3,929. Gradient banding on 256 colours was fixed by
quantising the gradient as a ramp, after three metric changes each broke palette derivation. The
width review measured every page at 200 columns, rearranged five, and left four alone for stated
reasons. Twice a measurement turned out to be measuring nothing, and the log says so.

## The problem

The owner sent a list: the Animation page (no app header, odd padding, no `ScrollView`, poor
resizing), disclosure keys, hover against focus, tab and border chrome, a reported wrong pick in a
scrolled menu, Split View feeling sluggish, "out-of-place colours" in gradients on a 256-colour
terminal, a question about how to model block borders, the Ctrl-A clash between `TextField` and
`TextEditor`, scroll granularity at a list's ends, mono image rendering, view resizing, the page
instruction lines, and a review of every Example page's use of horizontal space.

## How it unfolded

1. **First pass (2026-08-20).** The small items shipped (table below). The block-border question
   ("two enum cases or one with an associated value?") was answered "neither": a border of spaces is
   `BorderStyle.none`, already there, and a border of `█` takes the border colour like any glyph, so
   both became ordinary appearances. Gradient banding was diagnosed but not fixed: the OKLab metric
   in `nearestPalette256Index` charges chroma gain at x1 while its hue term is blind along the
   chroma axis, so a cell picks a blue=0 cube corner (80 points off) over a blue=95 neighbour (15
   off). Three metric fixes were measured and dropped, because the palette's surface walk reads the
   *quantised* colour and moves when the metric does. The Split View complaint could not be
   reproduced, and a measured table called it the cheapest page. The same measurements found the
   Lists page idling at 22.6% CPU (debug) because one `Spinner` per row forced whole-page re-renders:
   `_ListCore` dropped its rows' animated cells, so the run loop could not replay them.
2. **Split View, again.** The first measurements had dragged the box border one column beside the
   one-cell divider, so the drag had done nothing. With the right column a drag event cost 13 KB
   against an arrow key's 210 bytes. Writes are a blocking `write(2)` on the run loop's thread, so
   frame rate is terminal drain throughput divided by bytes per frame; a PTY drained at fixed rates
   reproduced the curve (30.6 fps unlimited down to 1.7 at 30 KB/s) with CPU falling in step, and
   `sample` put 94.8% of main-thread samples in `write`. The frame cap, event coalescing, discarded
   passes, measure cost and the divider's pulse were each ruled out with numbers.
3. **Second pass, "the four you called out".** Block borders paint their cells; select-all moved to
   Option-Ctrl-A so Ctrl-A is start-of-line in both text controls (Ctrl-E came with it); gradients
   quantise as a ramp, since `ColorDepth.current` turned out to be public all along, with the metric
   unchanged; and a frame stopped restating styling already in force, down 44% in escape count.
4. **Third pass.** The owner found the drag "maybe a little better and still quite poor". A frame
   wrote 3,906 cells to change 393. SGR became deltas from the known state inside a line, and
   `FrameDiffWriter` learnt span diffing, which the intra-line diffing note had parked on a cursor-blink
   measurement too small to matter. The debug build was found to cost 77.8 ms a drag frame against
   7.6 ms in release.
5. **Fourth pass (into 2026-08-21).** Otsu thresholding for mono images; design notes for an image
   palette and for view resizing, written before any code at the owner's request; the width review;
   a one-column left gutter in `ContentView`; and both open questions closed.

## What changed

| Found | Commit |
|---|---|
| A removal transition could not play for an `if` inside a stack | `211034812` |
| The Animation page laid out unlike the rest of the app | `497f1a7f8` |
| Left/Right disclosed in a `List` but not in `DisclosureGroup` or `OutlineGroup` | `486db394f` |
| Collapsing a group lost its contents' state (a deliberate divergence from SwiftUI) | `5fe032fcc` |
| Focus hid hover; hover moved one barely visible step | `6f16011c6`, `6709331cf` |
| The tint demo tinted with the accent itself under the default theme | `edf35d3d9` |
| A wheel-scrolled menu kept the old row lit, so release chose the wrong one | `e3de36d0e` |
| Alignment demos that showed what a guide is for | `5440e707d` |
| The main menu showed a localization key as a headline | `52fcd6443` |
| A tab's surrounding chrome was not part of its click target | `b682ae3b7` |
| A 256-colour tab body turned red under Amber | `cdbbf8249` |
| Border appearance names untranslated; block and blank appearances | `ace848b64`, `c0b58eed8` |
| A block border's seams showed through | `8d4497e56` |
| The focused scrollbar's thumb faded to the track's exact colour | `e4ef4ab11` |
| A spinner editor and a `.refreshable` indicator picker | `1e6c41c1a` |
| Ctrl-A meant different things in the two text controls; a key legend | `1d993b0b1`, `4a96706ce` |
| 256-colour gradient banding | `c1c2fbce8` |
| Drag frames restated styling, then restated changes absolutely | `32fa68a06`, `bd741b84f` |
| Drag frames rewrote whole rows | `ad9294519` |
| Mono images split at mid-grey, drawing 12% of sub-pixels as ink | `32228c44b` |
| Five pages narrow at 200 columns; one rearrangement reverted | "Finish the width review, including the page I rearranged and put back" (`68812b909`) |
| `handleMenuShortcut` was dead code (Q1) | `9399713a2` |
| A menu test clicked one row low on a clamped popup (Q2) | `836ceac52`, then `50e856885` |

The partial-row question was first answered wrongly in `1daeecee5`, then corrected in the log:
the bottom row already clipped, and `ListPartialRowTests` now pins both ends.

## Where it stands

- **The List spinner idle cost**, called the biggest performance item of the pass, was left as a
  session of its own. "A List row's own animation never reached the screen" (`aacff9f26`) landed the
  next day, and `6197d3615` (2026-09-24) moved the dropped-runs question onto the runs themselves.
- **Spans versus cursor moves.** Span diffing roughly doubled cursor moves (28 to 53 a frame).
  `FrameDiffWriter.spanMergeGap` (8) chooses bytes over escapes; the owner was asked to say if a
  terminal disagreed. Nothing in the log records an answer.
- **Width review**: Empty State and Image (File) are narrow by design, Split View already fills the
  width, and State Persistence and Preferences are prose-bound (two sentences side by side need 215
  columns), so their rearrangement was reverted rather than shipped as arrangements that never fire.
- **The image palette and view resizing** were designs on 2026-08-20; by the log's own status note
  of 2026-08-24 the tone LUT and `.userResizable(_:)` had shipped. The palette note's two questions
  for the owner (what a two-entry palette means; folding `.grayscale` in) are not answered there.
- **Deferred:** the concision sweep of about a dozen verbose help lines, each needing seven
  translations; the log lists their keys. The scroll-granularity selection toggle was deferred by the
  owner.
- **The log contradicts itself twice.** Its 2026-08-24 table calls Ctrl-A "still open" though
  `1d993b0b1` had changed both controls on 2026-08-20, and calls the left gutter open though the
  fourth pass reports it applied. Read the commits, not the table, on those two.

## For a future reader

- **A measurement that runs and reports can be measuring nothing.** The Split View table was taken
  while the drag did nothing (wrong column), and the first partial-row test swept a three-line wheel
  notch over three-line rows, so the top never clipped. Check that the input changes the screen
  before trusting any number about it.
- **When writes block, bytes are the frame rate.** CPU falling as frame rate falls is the signature
  of a blocked writer, not a slow one. Count bytes and changed cells before profiling CPU.
- **Measure debug and release separately.** A factor of ten on the same frame can swamp everything
  else a user sees under `swift run`.
- **Some metrics are load-bearing elsewhere.** `hueWeightedDistanceSquared` feeds palette derivation
  through quantised colours; retuning it for one symptom moved the surface walk. Fix sequences as
  sequences (the ramp quantiser) rather than tuning the per-sample metric.
- **Check a stated premise before building around it.** "The renderer cannot know the colour depth"
  and "the bottom cannot show a partial row" were both false, and each nearly sent the work the long
  way round.
- **Pick the right statistic.** "Widest row" mixed narrow pages with one long sentence and pages that
  are uniformly narrow on purpose; the median separated them.
- **PTY harness trap.** Feeding `pyte` in arrival-sized chunks splits multi-byte sequences
  differently per build and shows differences the bytes do not have. Capture the whole stream and
  replay it once.
- **Read where a popup lands, not where it asked to be.** Q2's "user-facing bug" was a test reading
  `overlay.offsetY` instead of the placed, composited frame.
