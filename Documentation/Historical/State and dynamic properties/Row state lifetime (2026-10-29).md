# Row state lifetime

*How long the state of a row in a windowing container (`List`, `Table`, a
lazy stack) lives, and what to do about the memory it holds. Measured against
SwiftUI and decided by the owner on 2026-10-29 (A+). Ids: none; the probe is
`Tools/SwiftUIProbes/Row state lifetime/`.*

## In short

A windowed row's state lives as long as its container, whether the row's id
is still in the data or not: SwiftUI's lazy containers do the same, measured,
and TUI already did. The memory that motivated the question — decoded
pictures in row state — is met by keeping pixels out of state instead: a
picture loaded from a file or a URL is kept by the image cache, bounded in
bytes, and its view holds a handle, holding the pixels only while drawn.

## The problem

Windowing containers draw only the rows meeting the viewport, so a row not
drawn this pass may have left the *window* only. Since `fa26a872`
(2026-07-16) each such container declares its own identity a *retained
subtree root* every pass it renders (`StateStorage.retainSubtree(_:)`), and
the end-of-pass prune keeps every descendant's state, drawn or not. So a row
whose id has left the data keeps its state too, until the container itself
leaves the tree. §5h of "Locating things without drawing them" recorded that
as deliberate, for the identity tax (knowing which ids left needs every id).

What it was thought to cost:

- **Growth.** A long-running app streaming rows through a list keeps every
  visited row's state: a chat whose rows decode an avatar into `@State` grew
  by about 8 MB an hour.
- **Stale state inherited** by a new item reusing an id.
- **Divergence from SwiftUI**, assumed to drop a removed row's state.

## How it unfolded

1. **2026-10-29, morning.** Asked to adopt "SwiftUI's rule" — a row's state
   lives exactly as long as its id is in the data — deterministically, with no
   amortised sweeps or caps. A design was made and built: each windowing
   container declared its keyed rows (the identity they hang under, the row
   type, and the data); at the end of a pass an O(1) test against the last
   declaration (the same buffer, a self-keyed `Range` still covering the old
   one) cleared nearly every container, and only where it could not, and an
   undrawn entry sat in a row, were the ids read (a prefix or suffix check,
   then a set of the ids) and the departed rows' state dropped. The quick
   Stress A/B was indistinguishable on every scenario. Hierarchical tables,
   `OutlineGroup` and stacks of mixed rows were left on the old rule.
2. **2026-10-29, afternoon.** Asked to extend it to every container, a probe
   was written to settle what SwiftUI does with an outline's collapsed
   children. It found that SwiftUI does not follow the rule at all in its lazy
   containers (below).
3. **2026-10-29, the owner: A+.** Keep SwiftUI's lifetime — TUI's existing
   behaviour — and move decoded pixels out of row state, so a long list's
   memory is bounded by the image cache rather than by every row ever drawn,
   with nothing an app can see changing. The keyed-row design was dropped
   unlanded. And align a collapsed `DisclosureGroup` in a non-lazy container
   with SwiftUI.

## Measured: what SwiftUI does

`Tools/SwiftUIProbes/Row state lifetime/rows.swift` (macOS 15.8.1, SwiftUI
6.5.4). Each row stamps its `@State` with a serial when SwiftUI makes it, and
logs the stamp, its `onAppear` and its `onDisappear`:

| Container | Id removed, then back on a later update | Collapsed, then expanded |
|---|---|---|
| `List { ForEach }` | `onDisappear`; back with its **old** `@State` — even after 300 other ids came and went | — |
| `LazyVStack { ForEach }` | `onDisappear`; back with its **old** `@State` (its body still runs while removed) | — |
| `VStack { ForEach }` | `onDisappear`; back **fresh** | — |
| `List(_:children:)`, `OutlineGroup` in a `List` | a child: `onDisappear`; back with its **old** `@State` | children: `onDisappear`; back with their **old** `@State` |
| `DisclosureGroup` in a `List` | — | content back with its **old** `@State` |
| `DisclosureGroup` in a `VStack` | — | content back **fresh** |

So in SwiftUI's lazy containers a row's state lives as long as the
container; only the lifecycle — `onDisappear`, task cancellation — follows
the data. That is what TUI does: no change to the rule, and no change to how
an app sees state behave.

## Where it stands

- **Row state** lives as long as its windowing container, as in SwiftUI's
  lazy containers (`StateStorage.retainSubtree(_:)`).
- **Pixels are not row state.** A picture loaded from a file or a URL through
  the image cache is `ImageLoadingPhase.cached`: the cache key, which decode it
  is (`ImageDecodeID`, one object per image the cache files, so a picture
  evicted and decoded again is another decode), and its size. The view holds
  the pixels while it is drawn (`ImagePixelPin`) and lets go when it
  disappears; what it converted them to is keyed by the decode
  (`DecodedPixels`), not by holding the buffer. A row drawn again reads them
  back from the cache. If the cache let them go, the picture loads again:
  a small file on that frame (`imageSynchronousDecodeLimit`), a larger file or
  a URL in a task, the row meanwhile showing what it last drew where it drew
  glyphs (`_ImageCore.lastDrawing`), or its placeholder where the terminal
  drew it as a picture — the terminal let that go when the row disappeared.
  An `AsyncImage` keeps its load the same way; it already fetched again on
  every reappearance, through the cache.
- **Not moved:** a picture made from pixels in memory (an `RGBAImage`, a
  `CGImage`, an `NSImage`) has nothing to be read back from, and a picture
  larger than the cache, or drawn outside an app (no cache), has nowhere to
  go: those stay in state, as before. An `ImagePaint` keeps the pixels it
  converted the picture to, for the paint's equality.
- **Measured:** a column of 1,000 distinct 16 × 16 pictures scrolled through
  under a cache of 32 pictures holds at most the pictures on screen in state
  (`ImagePixelsOutOfStateTests`), where it held all 1,000.
- **`DisclosureGroup`** in a non-lazy container drops its content's state
  when it collapses, and starts it afresh when it expands, as SwiftUI's does;
  in a `List` it keeps it, as SwiftUI's does.

## For a future reader

- The probe ran on macOS only. iOS's `List` (a collection view) may differ;
  re-run before relying on either for a parity argument.
- If row-state growth matters again, it is state other than pixels that
  remains: glyph conversions (a few kilobytes a picture), and whatever an app
  keeps in its rows' `@State`. SwiftUI keeps the same.
