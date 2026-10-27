# Content past a scroll view's edge

*`scrollClipDisabled`: a scroll view's content drawn past its viewport, over
its neighbours, and what a later view hides of it. Ids: A10, B-D2S-4,
B-D2S-5, D2S-SCROLLCLIP; B-LISTS2-5 for `Table`.*

## In short

Under `scrollClipDisabled()`, a `ScrollView` draws the content past its
viewport as a floating layer around itself, with its hit regions, and a
`List` draws the row before and after its window just outside its frame. A
later view hides the overflow under each run of cells it paints; its blank
cells, between its words too, show the overflow, as SwiftUI's transparency
does. A `Table` still clips.

## The problem

SwiftUI composites in points: a later view hides only where it actually
draws, glyph by glyph. A terminal cell holds one glyph, so "where it draws"
had to be said in cells, and the rule chosen decides both what is drawn and
which view a click lands on.

## How it unfolded

1. **The owner's A10** asked for it on `ScrollView`; lane D2S built it, with
   the per-line rule for what a later view hides (B-D2S-5) and click routing
   that follows the drawing.
2. **`List` and `Table`.** SwiftUI's `List` honours the modifier on macOS
   (measured). Lane LISTS2 built it for `List` on 2026-10-19; `Table`, with
   its two composers, still clips (B-LISTS2-5, about half a day).
3. **The fuller transparency.** Asked on 2026-10-18 whether the overflow
   should also show through the blank cells *inside* a later line (between
   its words), the recommendation was no: two texts interleaved cell by cell
   are hardly legible. On 2026-10-26 the owner leaned to SwiftUI's behaviour
   and asked whether it had downsides beyond the look — performance — and to
   build it if it is cheap, with an A/B of the geometry (D2S-SCROLLCLIP).
   Built 2026-10-27 (lane SCROLLCLIP); its A/B is owed for a quiet machine.

## Where it stands

Run-by-run hiding, shipped 2026-10-27 (D2S-SCROLLCLIP), its A/B owed.

## For a future reader

- **Owed: D2S-SCROLLCLIP's A/B** (Stress `geometry` and any scenario that
  draws overflow), the owner's condition being that it be cheap. Only a
  buffer that carries overflow pays anything: the cut runs where a later view
  meets overflow, and reads more rects than before only where its lines have
  blanks between painted cells.
- **`contentShape`.** When TUI has one, a later view's shape should cut the
  overflow's hit regions as a painted cell does (B-D2S-5 says why).
- **`Table` clips under the modifier** until B-LISTS2-5 is built; a list's
  overflow rows are drawn but not clickable (about two hours more).

## The record

### B-D2S-4. `scrollClipDisabled` reaches `ScrollView`; `List` and `Table` keep clipping

*`View.scrollClipDisabled(_:)` (A10)*

The owner's A10 decision is about the scroll view: its content past the
viewport draws as a floating layer around it, over the neighbours, with its hit
regions. That ships for `ScrollView`. SwiftUI's `List` on macOS honours the
modifier too (measured on macOS 15: rows draw on below a 100-point list's frame
when it is set, and do not when it is not), and TUI's `List` and `Table`
still clip: the modifier compiles on them and changes nothing.

**The fuller version:** a list draws only the rows its window walks, so it
would draw a row or two past each edge under the modifier (its band, as a lazy
stack's), and hand them out as the scroll view's overflow layers are; the
header, the border and the indicators stay where they are. About half a day
for both, with tests, and no cost to a list without the modifier.

**`List`: built (2026-10-19, lane LISTS2).** Under the modifier a list draws
the row before its window and the one after — each with the lines of the
window's edge row the window cut — just outside its frame, as overflow layers
at its place in the stacking order, composed as its rows are (the cursor's and
the selection's looks, the stripes). They are drawn, not clicked: the list's
click mapping covers its frame, and carrying the rows' own regions and a
row click out to them is about two hours more. A `Table` still clips: its two
composers (single- and multi-line rows) each need the same, about half a day
(lane LISTS2's decisions, B-LISTS2-5).

### B-D2S-5. A later view hides an unclipped scroll view's overflow from its first painted cell to its last

Under `scrollClipDisabled`, the content after a scroll view hides the scroll
view's overflow where that content draws — SwiftUI's stacking (measured). A
terminal cell is drawn or not, so "where it draws" has to be said in cells.
Shipped: on each line of the later content, from its first painted cell (a
glyph other than a space; a space styled to show — a background, reverse
video, an underline, a strikethrough, an overline; or a cell an animated run
repaints) to its last; the unstyled blank
cells either side — a stack's alignment padding, an overlay's `Spacer`, an
`.offset` view's empty footprint — hide nothing, and the overflow shows there
as SwiftUI's does. The overflow is drawn by the same rule: its blank cells at
either end of a line draw nothing and take no click.

**Clicks follow the drawing.** A TUI tap covers its view's whole frame,
padding included, and where the overflow draws over a later view's padding the
overflow takes the click there: `Text("OK").frame(width: 12,
alignment: .leading).onTapGesture { … }` under a scroll view whose row 2 runs
down into it draws "OKw 2", and a click on the "w 2" is row 2's, while "OK" and
the padding past the overflow's last cell stay OK's. That is SwiftUI's routing
for a view with no `contentShape` — its padding is not hit at all — and the
alternative, the later view keeping its frame under the overflow, sends a
click on visible overflow text to the view beside it. With a `contentShape`
SwiftUI's later view takes that area; TUI has no `contentShape` yet (a
baseline gap waiting on shapes), and when it lands its shape should cut the
overflow's regions as a painted cell does. Pinned by
`laterViewPaddingClicksFollowTheDrawing`.

**The fuller version:** treat EVERY unstyled blank cell as transparent, inside
a line too, so the overflow shows between the words of a later `Text` as it
does between SwiftUI's glyphs. It is a small change (cut per run of painted
cells rather than per line, an hour or two with tests, no cost where nothing is
unclipped), but two texts interleaved cell by cell are hardly legible, which is
why it is not the default. Owner's call.

**Fuller version shipped (lane SCROLLCLIP, 2026-10-27; D2S-SCROLLCLIP, the
owner's lean of 2026-10-26 to SwiftUI's behaviour).** A later view hides the
overflow under each run of cells it paints (`String.paintedRuns()`,
`FrameBuffer.paintedBlocks(inRows:)`), so the blank cells between its words
show the overflow too: `Text("a    b")` under row 2 of an overflowing scroll
view draws `aow 2b`. Clicks follow the drawing as before: a click on the
overflow shown between the words is the overflow's. The overflow itself is
still drawn from its first painted cell to its last on each line. The test is
`ScrollClipDisabledTests.blanksBetweenWordsShowTheOverflow`; the A/B is owed.
