# Safe areas, size classes and layout direction

*What TUI does with SwiftUI's environment of the device: the safe area, size
classes, the layout direction and its mirroring. Ids: B1, A3, B3, B6, B25;
deviation L10; right-to-left, deferred.*

## In short

There is no safe area: `safeAreaInset` and `safeAreaBar` lay the bar beside
the view (L10), and `safeAreaPadding` is padding, or a scroll view's content
margin along the axes it scrolls. Size classes default to `.regular` and are
the app's to set; where an app writes `.compact`, TUI adapts as iOS does (a
popover becomes a sheet, a split view collapses, a table shows its first
column, a sidebar tab view becomes a strip). The layout direction is always
left to right and is read-only; right-to-left support, with
`layoutDirectionBehavior`, is wanted and deferred.

## How it unfolded

1. **2026-10-04 to 05.** The owner asked what a safe area is worth (very
   little here: no notch, no system bars, and the payoff is colour under a
   bar's blank cells), what compact size classes would cost, and whether
   `layoutDirectionBehavior` could mirror now (it would need the same buffer
   mirror right-to-left needs; deferred with it, option 2 of A3).
2. **2026-10-12, the owner.** The real safe area (SA-B) is not built; size
   classes follow what an app sets, changing no default; right-to-left is still
   wanted, after everything else.
3. **2026-10-13.** The compact adaptations shipped (B3; the popover and split
   view under A21, in the presentation stories).

## Where it stands

As above. The symbols that would observe a safe area (`ignoresSafeArea`,
`SafeAreaRegions`, `GeometryProxy.safeAreaInsets`) stay refused, so no ported
code can depend on one; the four text-direction strategies of wave 11 wait
with A3.

## For a future reader

- **Right-to-left is owed after the SwiftUI compatibility work** (the owner,
  2026-10-12). It needs a per-terminal survey first: terminals reorder bidi
  text themselves, inconsistently, and only VTE lets an app turn that off.
- **SA-B becomes worth building** only if toolbars want content scrolling under
  them, or the scroll-edge effects (refusal review O7) are to mean something.
- **A terminal narrower than some width could report `.compact`** for free; the
  run loop already publishes the size. Not asked for.

## The record

### B1. `\.layoutDirection` is read-only (always left-to-right)

SwiftUI's is settable, and under `.rightToLeft` its views mirror everything
that runs along the horizontal axis:

- stacks;
- `leading`/`trailing` alignment and insets;
- text alignment;
- images that are marked to flip.

TUI's views do none of that yet, so a write would be accepted and
ignored. The setter is left out instead, so the write fails to compile.

**The fuller version** is real right-to-left support. Every layout site that
resolves leading/trailing to left/right would consult the direction:

- `HStack` placement order;
- `Alignment` and `EdgeInsets` resolution;
- `Text` wrapping and alignment;
- `List` chrome (disclosure indicators, separator insets);
- scroll bars, which go on the leading side in RTL.

It also needs `layoutDirectionBehavior(_:)` (A3), and
`flipsForRightToLeftLayoutDirection(_:)`, which ships as the identity —
correct while the direction is always left-to-right — must start mirroring.

That is several days, and every one of those sites gets a test. Bidi text
itself (reordering mixed-direction runs) is a separate and larger question,
because the terminal does some of it on its own and inconsistently. That
belongs in `Terminal compatibility survey.md`, measured, before any design.

**Your answers (2026-10-04, 2026-10-12):** right-to-left is still wanted, and
out of scope for now: pinned until there is a solid plan, after everything
else. A3 and B8's mirroring wait on it.

### A3. `layoutDirectionBehavior(_:)`: mirror now, or with right-to-left?

*`LayoutDirectionBehavior` (`.fixed`, `.mirrors`, `.mirrors(in:)`),
`View.layoutDirectionBehavior(_:)`, `Shape.layoutDirectionBehavior`*

Measured in SwiftUI: in a left-to-right environment `.fixed` and `.mirrors`
change nothing, but `.mirrors(in: .leftToRight)` really mirrors. So this
cannot ship as a no-op, and one enum case cannot be made a compile error.

**Options.**

1. **Mirror at cell level now.** Reverse each row's cells (wide characters
   kept whole), swap glyphs that have mirror forms (Unicode's mirroring
   pairs, plus `┌↔┐`, `╭↔╮`, `├↔┤`, `▌↔▐`, arrows), and mirror the x of every
   payload (hit regions, floating layers, opacity regions, animated runs).
   Letters come out reversed, not mirror-written. 1–1.5 days.
2. **Defer to right-to-left support** (B1's fuller version), which needs the
   same buffer mirror and would give it real use and tests.

**Recommendation:** 2. Nothing ships until then.

**Decided 2026-10-04: defer with right-to-left** (option 2; you left it to
me). You also raised that a terminal's own bidi may mirror a Hebrew line a
second time. That is the per-terminal survey right-to-left needs first: TUI
already puts invisible left-to-right marks round its image glyphs to stop
terminals reordering them, and one terminal (VTE) lets an app turn its
reordering off; most do not (answer of 2026-10-05).
`flipsForRightToLeftLayoutDirection(_:)` has shipped regardless: its
condition is a right-to-left environment, which cannot occur yet (B1).

**Wave 11 adds four symbols to the same question:**
`View.multilineTextAlignment(strategy:)`, `View.writingDirection(strategy:)`,
`Text.AlignmentStrategy` and `Text.WritingDirectionStrategy`. Each strategy
chooses between the layout direction and a paragraph's own writing
direction. TUI lays every paragraph out left to right, so the two agree
except on a right-to-left paragraph. There, `.writingDirectionBased` and
`.contentBased` would right-align a Hebrew line in SwiftUI and left-align it
here. Shipping them before right-to-left would be a quiet lie for exactly
the text they exist for, so they wait with this entry.

*Wave 10's entries (A6–A12, B23–B31, C6; C7 shipped 2026-10-18 in lane PARITYMISC): SwiftUI behaviour quoted as *measured* was measured on macOS 15 with an offscreen `NSHostingView`; the probes are in `Tools/SwiftUIProbes/Scroll geometry, margins and the wheel (wave 10)/`.*

### B3. Size classes are settable, and nothing TUI draws reads them

`\.horizontalSizeClass` and `\.verticalSizeClass` default to `.regular`, as
macOS reports for any window. They are settable, as SwiftUI's are, for an
app's own views to read.

I believe macOS's own views ignore a written `.compact`, but I have not been
able to confirm that for `NavigationSplitView`. On iOS, compact collapses a
split view into a stack.

If you would rather a terminal narrower than some width report `.compact`,
that is a cheap change: the run loop already publishes the terminal size each
frame. It would make split views worth teaching to collapse.

The same reasoning covers `\.displayScale` and `\.isLuminanceReduced`:

- They are settable channels, and nothing TUI draws reads them.
- macOS's text ignores both; that was measured.
- `\.dynamicTypeSize` is the same, which also answers the old refusal of
  `DynamicTypeSize`. The refusal was true about terminals and wrong about
  the API, because macOS reads `.large` and ignores writes for text too.

**Decided 2026-10-12: follow what an app sets, and change no default.** An
app decides when a class is `.compact`, and TUI adapts where it can. (You
asked the cost on 2026-10-04; the 2026-10-05 answer priced reporting
`.compact` at nothing and the views that adapt to it, chiefly a split view
collapsing, at one to two days.) Since A6, `.viewAligned` reads both classes
for its paging limit; nothing else does. Following a written `.compact` means,
by SwiftUI's own behaviour on iOS and iPadOS:

- a popover adapts to a sheet (`presentationCompactAdaptation`, A21);
- `NavigationSplitView` collapses into a stack showing
  `preferredCompactColumn` (A21);
- `Table` hides its headers and every column after the first (Apple's
  `Table` documentation);
- a `.sidebarAdaptable` `TabView` shows tabs instead of a sidebar.

`\.dynamicTypeSize` and `\.displayScale` stay channels nothing reads: the
terminal owns the font and the cell size. **Lane owed:** 5–7 commits, about 3
days (estimate): the popover adaptation, the split-view collapse, the compact
`Table` and the compact sidebar tab view, each with tests.

**2026-10-13:** the popover adaptation and the split-view collapse shipped
(A21), and the compact `Table`: no header line, and its first column alone
(the first the customization shows) across the table's width, whatever
width the column was given, since on iPhone the table is a list of that
column. Then the compact sidebar tab view: a `.sidebarAdaptable` tab view
draws the default strip in a compact class, of the tabs a strip shows (no
sidebar-only tabs, no section headers), reporting `.topBar` and no
sections, and its core keeps its place so the selected tab's content keeps
its state. The lane is done; what it left is listed under A21.

### B6. `safeAreaInset` puts the bar beside the view; there is no safe area

*`View.safeAreaInset(edge:alignment:spacing:content:)` (both edge types),
`View.safeAreaBar(edge:alignment:spacing:content:)` (both); still refused:
`View.ignoresSafeArea(_:edges:)`, `SafeAreaRegions`,
`GeometryProxy.safeAreaInsets`, and the `ignoresSafeAreaEdges:` overloads of
`background`/`overlay`*

SwiftUI's `safeAreaInset` does two things: it lays the bar beside the view,
and it grows the view's safe area by the bar. Measured (W05 brief, probes E
and q13–q15), the second is what lets a `ScrollView` run *under* the bar, a
style `.background(.red)` extend beneath it, and `ignoresSafeArea()` reach
into it.

**Shipped:** the first half only. The bar sits beside the view, which is
proposed what the bar leaves; spacing `nil` is none (measured), a bar wider
than the view sets the width, `alignment:` places the bar across the view, and
two bars stack outward. `safeAreaBar` lays out identically — its extra is the
scroll-edge effects, which need content under the bar. The bar renders at the
layer identity `.overlay` uses, so adding one moves no `@State`.

**What this gives up, silently:** in ported code, a scroll view stops at the
bar instead of running under it, and an existing style background on the
view does not extend beneath it. In a cell grid that is visible only as
colour under the bar's blank cells — the bar's glyphs cover anything under
them — and nothing that would *observe* a safe area compiles, so no code can
depend on one being there.

**The fuller version (SA-B)** is a real safe area: a `safeAreaInsets` value
set by the producers and propagated by adjacency through every container
(stacks, `ZStack`, `Layout`, `Grid`, frame, padding — which consumes it —
overlay/background, and `ScrollView`/`List`, which turn it into content
margins and extend their viewport under the bar); `ignoresSafeArea`; style
backgrounds and overlays extending; `GeometryProxy.safeAreaInsets`;
`SafeAreaRegions`. Four to six days, a context field on the layout hot path
(a single `Int` there has measured +2.4%), and a measure/render-parity risk at
every container that decides adjacency — for colour under a bar's blanks. It
is the route if the scroll-edge effects (refusal review O7) are to mean
something.

`safeAreaPadding` shipped with Wave 10's `contentMargins`: for non-scrolling
content it is padding, and for a scroll view it is a content margin along the
axes it scrolls (B25).

**Decided 2026-10-12: SA-B is not built.** You asked on 2026-10-04 what
safe-area support is worth. The 2026-10-05 answer: very little here. With no
notch and no system bars, the only producers would be TUI's own bars, and
the payoff is colour under a bar's blank cells; it would matter only if
toolbars wanted content scrolling beneath them. You were not convinced, so the
half that shipped is the behaviour, kept as a deliberate deviation
([Deliberate deviations from SwiftUI.md L10](<../../SwiftUI parity/Deliberate deviations from SwiftUI.md#l10-safeareainset-puts-the-bar-beside-the-view-there-is-no-safe-area>)). The
refused symbols above stay refused, and B25's fuller version, which is SA-B,
goes with it. The entry stays as the record of what the declined version was.

### B25. `safeAreaPadding` is padding, or a scroll view's content margin

*`View.safeAreaPadding(_:)` (both), `View.safeAreaPadding(_:_:)`*

As B6 planned. Measured in SwiftUI: on a vertical `ScrollView`,
`safeAreaPadding(15)` puts 15 of content inset at the top and bottom (it
scrolls with the content, and adds to `contentMargins`) and narrows the view
itself by 30 — across its axis it is padding. Nested calls add.

**Shipped:** exactly that geometry, for a `ScrollView` that is the modifier's
content itself or behind modifiers that only set the environment
(`.scrollIndicators`, `.contentMargins`, `.scrollPosition` and the like).
Anything else — including a scroll view behind `.padding` or `.frame`, which
in SwiftUI does not reach the edges the safe area is on — is padded.
`nil` is one cell, what SwiftUI's 16-point default is to `.padding()`.

**What this gives up**, and B6 already accepted: SwiftUI also extends a
`List` or a `TextEditor` into the safe area and insets its rows (measured: a
`List`'s first row moves down 40 under `safeAreaPadding(.top, 40)`, with the
list itself still at the top). Here those are padded whole, so their chrome
moves in with their rows. The fuller version is B6's real safe area, which
you declined on 2026-10-12, so this stays as shipped.
