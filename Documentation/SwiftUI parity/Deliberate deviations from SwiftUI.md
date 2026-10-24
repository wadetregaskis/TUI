# Deliberate deviations from SwiftUI

TUIkit aims at rough source compatibility with SwiftUI: SwiftUI code should
compile and mean the same thing, except where a grid of character cells cannot
carry the meaning. The two rules behind that are at the top of
[SwiftUI compatibility guide.md](<SwiftUI compatibility guide.md#two-rules-that-decide-every-case>).

This page lists the places where code that compiles against both frameworks
behaves differently **on purpose**. It is about the behaviour of SwiftUI
features and APIs TUIkit has, not about what TUIkit adds or leaves out.

## What belongs here

An entry belongs here when all three hold:

- the SwiftUI spelling compiles against TUIkit;
- it does something observably different from what it does in SwiftUI. Each
  entry says how SwiftUI's side is known: measured, Apple's documentation, the
  SDK's declaration, or "not measured" where it is only believed;
- the difference was chosen: by an owner's ruling, by a decision recorded in
  the decisions files or on the declaration, or because a terminal leaves no
  alternative.

These do not belong here:

- **APIs TUIkit declines.** They fail to compile, which is rule 2 working:
  `Tools/APIParity/parity-map.json` (`notImplemented`) and
  [§4b](<SwiftUI compatibility guide.md#4b-swiftui-has-it--tuikit-wont-bitmap-vs-text-cell>) of the compatibility guide. The `ObservableObject`
  family is the best-known one ([§2.3](<SwiftUI compatibility guide.md#23-reactive-model-is-observable-only-no-observableobject-family>)).
- **TUI-only additions** ([§4c](<SwiftUI compatibility guide.md#4c-tuikit-only-no-swiftui-equivalent>)) and **SwiftUI APIs not built
  yet** ([§4a](<SwiftUI compatibility guide.md#4a-swiftui-has-it--tuikit-should-add-it>)).
- **Behaviour that differs between terminals.** That is measured per host in
  [Terminal compatibility survey.md](<../Terminals/Terminal compatibility survey.md>).
- **Bugs.** A difference nobody chose is a defect. Give it a failing test and
  fix it, or put it to the owner; if the ruling is to keep it, it comes here.
  Differences that are known and slated to change, or still open, are listed
  at the end, in [Slated to change](#slated-to-change).

Each entry gives a **status**:

| Status | Meaning |
|---|---|
| **Owner** | The owner ruled on it (dated). |
| **Recorded** | Written down as deliberate in the compatibility guide or on the declaration; no owner ruling is on record. The five that awaited a ruling were answered on 2026-10-13: T8 keeps its filter and gains a bell, and L12, T10, E3 and V7 are closed (the stacks give space by `layoutPriority`; an interpolated key is looked up as SwiftUI spells it too; `\.locale` carries the user's region; a picker's options and a text field's suggestions are read through the member resolution). L14, found the same day, was closed the same evening: a row shares its width among children of one priority as SwiftUI's does (a column is slated to follow). |
| **Lane** | The safe option a lane shipped, written up as a B entry in a decisions file with its fuller version priced. The owner may still revisit it. |
| **Medium** | Forced by what a terminal reports or can draw. Keeping SwiftUI's behaviour is not possible, only approximating it. |
| **Under review** | Kept for now; the owner has an open question on it. |

## How to add an entry

1. Put it in the area it belongs to, under the next free ID. IDs are never
   reused, so a link to `L3` keeps meaning the same thing.
2. Fill the four fields. **SwiftUI**: what it does, and how that is known
   (measured, with the date and the probe; Apple's documentation; the SDK's
   declaration; or "not measured"). **TUIkit**: what it does, naming the
   declaration or the test that pins it. **Why**: the reason, in a sentence or
   two, or "not recorded" where the decision gives none. **Decided**: where,
   as a link, and the status.
3. Land it in the same commit as the behaviour. A commit that removes a
   deviation deletes its entry and says so in its message.
4. Before "fixing" a difference from SwiftUI, look for it here. Closing a
   deliberate deviation is a regression, not parity.

Units are cells throughout: a *column* is a cell's width and a *row* its
height. Where SwiftUI's numbers are compared with TUIkit's, a typical cell is
taken to be 8 points wide and 16 tall (the figure decisions B-D2C-3 uses).

## Areas

- [Units and geometry](#units-and-geometry)
- [Layout](#layout)
- [State and data flow](#state-and-data-flow)
- [Environment](#environment)
- [Focus and input](#focus-and-input)
- [Text](#text)
- [Colour and drawing](#colour-and-drawing)
- [Animation](#animation)
- [Scrolling](#scrolling)
- [Lists, tables and controls](#lists-tables-and-controls)
- [Presentation and window chrome](#presentation-and-window-chrome)
- [Lifecycle](#lifecycle)
- [Slated to change](#slated-to-change)

---

## Units and geometry

### U1. Measurements are whole cells, not points

- **SwiftUI:** `.padding(20)`, `VStack(spacing: 8)`, `.frame(width: 120)` and
  `.offset(x: 4)` are `CGFloat` points (the SDK's declarations).
- **TUIkit:** the same spellings take `Int` cells. `.padding(20)` is twenty
  columns at each side and twenty rows above and below, so an integer literal
  ported from SwiftUI means about 8 times as much across and 16 times as much
  down. A fractional `CGFloat` expression does not compile. A frame's
  maximum is a `FrameDimension`, which an integer literal is, so
  `.frame(maxWidth: 200)` compiles and fills its offer up to 200 columns, as
  SwiftUI's does up to 200 points; a `CGFloat` variable needs `.fixed(Int(…))`.
- **Why:** a terminal addresses whole cells. Half a column cannot be drawn, and
  `CGFloat` would push a rounding decision onto every call site.
- **Decided:** [§2.1](<SwiftUI compatibility guide.md#21-interface-measurements-are-int-not-cgfloat>); the owner names `.padding(20)` as a
  deliberate choice (2026-10-11). **Owner.**

### U2. Geometry values are cell types

- **SwiftUI:** `CGPoint`, `CGSize`, `CGRect` and `CGVector`, in points (the
  SDK's declarations). `UnitPoint`, fractions of a box rather than points, is
  SwiftUI's own in TUIkit too.
- **TUIkit:** `CellPoint`, `CellSize` and `CellRect` of `Int` cells, and
  `CellVector` (a rate, `Double` cells per second). Pointer locations,
  `GeometryProxy.size` and `frame(in:)`, `Layout.placeSubviews(in:)`, anchors
  and `DropInfo.location` all use them. `CellRect` has no `midX`/`midY`;
  `LayoutSubview.place(in:anchor:proposal:)` resolves an anchor in one
  flooring step. An alignment guide's value stays `Double`, so a guide behaves
  as SwiftUI's does: it is floored only after one guide is subtracted from
  another. An anchor kept in `@State` and read in another subtree resolves
  through the global space, from where the anchored view was when the last
  frame was drawn ([§1](<SwiftUI compatibility guide.md#1-match>), the Env / prefs row).
- **Why:** U1's reason. Flooring a midpoint before subtracting a half-size
  moves a centred view by a cell in 210 of 861 (extent, size) cases.
- **Decided:** [§2.2](<SwiftUI compatibility guide.md#22-geometry-is-integer-never-cgpointcgsizecgrect>), [B-D5G-5](<Decisions/Layout and geometry/Coordinate spaces, geometry and scroll visibility (D5G).md#b-d5g-5-cellrect-gains-minx-miny-origin-and-size--and-still-no-midxmidy>). **Recorded.**

### U3. Default spacing and padding are one cell or none

- **SwiftUI:** a stack's `spacing: nil` uses the views' preferred spacing,
  `.padding()` a platform-specific default amount, `Grid` platform metrics
  (Apple's documentation; the amounts were not measured).
- **TUIkit:** `nil` is 0 rows between the views of a `VStack` and 1 column in
  an `HStack`; a `Grid` is 1 column and 0 rows; a lazy grid's `nil` is no
  blank rows or columns. `.padding()`, `scenePadding` and
  `safeAreaPadding(nil)` are one cell on each edge.
- **Why:** terminals are dense. A blank column reads as a word gap and a blank
  row as a paragraph break; adjacent lines are already apart.
- **Decided:** [§2.1](<SwiftUI compatibility guide.md#21-interface-measurements-are-int-not-cgfloat>) (its note on stacks),
  [§1](<SwiftUI compatibility guide.md#1-match>) (the Grid and Lazy grids rows), [B25](<Decisions/SwiftUI API completion decisions.md#b25-safeareapadding-is-padding-or-a-scroll-views-content-margin>).
  **Recorded.** A row resolves `nil` per pair of views: none beside a custom
  `Layout` that asks for none on that edge ([B20](<Decisions/SwiftUI API completion decisions.md#b20-a-stacks-spacing-nil-is-resolved-per-pair-of-neighbours>)),
  except one inside an `AnyView`, which keeps the column here ([B-BITEMS1-3](<Decisions/Default focus, drop badges and stack spacing (BITEMS1).md#b-bitems1-3-a-rows-spacing-nil-per-pair-reaches-layouts-and-the-wrappers-that-move-no-edge>)).

### U4. Gesture distances are cells along either axis

- **SwiftUI:** Euclidean points: a drag starts after 10, a long press fails
  past 10, a tap fails past 40 (measured, macOS 15.8, by lane 17g's probes,
  `Tools/SwiftUIProbes/Gestures (lane 17g)/`, as the decisions file's note on lane 17g says).
- **TUIkit:** whole cells along either axis. A drag and a long press allow one
  cell by default, the smallest move a terminal reports; a tap allows five
  columns or two rows. `DragGesture(minimumDistance: 10)` written for SwiftUI
  asks for ten cells.
- **Why:** a terminal reports the pointer by cell.
- **Decided:** [B90](<Decisions/SwiftUI API completion decisions.md#b90-distances-are-cells-along-either-axis>). **Lane** (the fuller version converts points
  through the reported cell size).

### U5. A shape's unit is square

- **SwiftUI:** `Shape.path(in:)` is handed the view's frame in points, square
  on screen; a `lineWidth`, a `cornerRadius` or a dash is in points (the SDK's
  declarations).
- **TUIkit:** the frame is handed in square units: its columns across, and its
  rows times `\.imageCellAspect` (about 2, the cell's height over its width;
  2 where the terminal does not report it) down. A shape computed from the
  rectangle keeps its proportions — a circle is round — and every literal
  length is in columns, so `lineWidth: 1` is a column wide and half a row tall
  where it runs along a row. A shape's `sizeThatFits(_:)` answers in cells, as a
  custom `Layout`'s does (`ShapeTests`, `PathTests`).
- **Why:** in cells a circle would be twice as tall as it is wide; in pixels the
  numbers are large and wrong by up to 2.3× where the terminal does not say its
  cell size. The aspect is a ratio, in which the display scale cancels.
- **Decided:** [O0](<Refusals re-examined, wave 17 (2026-10-03).md#o0-shapes-the-unit-of-shapepathin--gates-w1>),
  ruled 2026-10-12: (B); [§2.12](<SwiftUI compatibility guide.md#212-a-shapes-unit-is-square-a-column-across-the-same-down>). **Owner.**

---

## Layout

### L1. A fixed `.frame` aligns its content top-leading

- **SwiftUI:** `frame(width:height:alignment:)` defaults to `.center` (the
  SDK's declaration).
- **TUIkit:** `.topLeading`
  ([View+Layout.swift](../../Sources/TUIkitFoundation/Extensions/View+Layout.swift#L285-L298)).
  The flexible `frame(minWidth:…maxHeight:alignment:)` keeps `.center`.
- **Why:** in a terminal a fixed width nearly always makes a left-aligned
  column: a label gutter, a slider channel, a table cell. Centring by default
  would shift every such column.
- **Decided:** [§2.7](<SwiftUI compatibility guide.md#27-fixed-frame-default-alignment-is-topleading-not-center>). **Recorded.**

### L2. The stack layouts default to leading, top and top-leading

- **SwiftUI:** `VStackLayout`, `HStackLayout` and `ZStackLayout` default to
  `.center`, like the stack views (the SDK's declarations).
- **TUIkit:** they default to `.leading`, `.top` and `.topLeading`. `VStack`,
  `HStack` and `ZStack` keep `.center`. So `AnyLayout(isWide ? HStackLayout() :
  VStackLayout())` is not a silent stand-in for the stack views where the call
  site relied on their centring.
- **Why:** L1's top-left reading, extended to the layout values.
- **Decided:** [§2.10](<SwiftUI compatibility guide.md#210-vstacklayout--hstacklayout--zstacklayout-default-alignment-is-leading--top--topleading-not-center>). **Owner** (2026-09-20).

### L3. Lazy stacks honour alignment guides

- **SwiftUI:** `LazyVStack` and `LazyHStack` ignore an explicit
  `.alignmentGuide`: each row sits at its alignment's default (measured,
  macOS 15.8, 2026-10-11, inside and outside a `ScrollView`, in a `ForEach`,
  with `Text` rows). The eager stacks honour it.
- **TUIkit:** the lazy stacks honour it as the eager ones do, on the placed and
  the windowed paths (`AlignmentGuideRun`; pinned by
  `AlignmentGuideModifierTests` and `AlignmentGuideContainerParityTests`).
- **Why:** SwiftUI's behaviour looks like a bug, and it is undocumented: its
  lazy stacks also report no guide to their parent, not even a custom one
  (measured). No SwiftUI code can rely on a guide doing nothing, and copying it
  would make a guide silently inert in one kind of stack.
- **Cost:** paid only where a lazy row's type carries a guide. Then the uniform
  window (at any row count) and the anchored window (over 256 rows) step aside,
  and the exact slot walk measures every row on every frame, which is what
  keeps the alignment column still as rows scroll in. Not measured on a big
  list.
- **Decided:** [A-GUIDE-1](<Decisions/Layout and geometry/Alignment guides outside their view (GUIDE).md#a-guide-1-swiftuis-lazy-stacks-ignore-an-explicit-alignment-guide-tuikits-honour-it--decided-keep-honouring-it>). **Owner** (2026-10-12: keep).

### L5. A view does not draw outside the size it reports

- **SwiftUI:** a frame does not clip
  ([`clipped(antialiased:)`](<SwiftUI compatibility guide.md#29-what-clips-a-floating-layer-and-how-far-a-spring-may-carry-a-view>) documents this). An overlay larger
  than its base, an image larger than its frame, and a child an alignment guide
  pushes past its frame all draw outside it, cut only by the window or a
  clipping view. A stack whose guides need more room than it was offered
  reports the larger size (measured, B-GUIDE-1, B-GUIDE-3).
- **TUIkit:** a container reports at most what it was offered and draws into a
  buffer of that size. An oversized overlay is cut to its base's box. An image
  larger than its space is cut from its top-leading corner, where SwiftUI's
  overflows centred — except in a `.frame`, an `.overlay` or a `.background`,
  which since 2026-10-18 place a view drawn at its own size (an image at its
  natural size, `.fixedSize()`) by their alignment and draw what lies past
  them past them, as SwiftUI does (B-GUIDE3-1). What a placement puts outside
  its region is the other exception (since 2026-10-12): a single child whose guide places it outside
  its `.frame`, `.overlay` or `.background` is drawn there, as SwiftUI's is, at
  its place in the stacking order and clicked where it is drawn, and a run of
  guided views larger than a region that cannot grow keeps every guide on one
  line and draws the overhang past the region's edge, where SwiftUI's stack
  reports the larger size instead (`PlacementOverflowTests`).
- **Why:** a terminal buffer has no outside. A view that reported one size and
  drew another would leave every container above it guessing, and measuring
  would stop agreeing with drawing.
- **Decided:** [§1](<SwiftUI compatibility guide.md#1-match>) (the Modifiers row, on `overlay`),
  [B-D3M-2](<Decisions/Presentation and windows/Dialogs, image sizes, format styles and reduce motion (D3M).md#b-d3m-2-an-images-natural-size-is-known-on-four-hosts-and-ghosttys-only-locally>), [B-GUIDE-1](<Decisions/Layout and geometry/Alignment guides outside their view (GUIDE).md#b-guide-1-a-region-smaller-than-the-run-keeps-the-runs-leading-edge-on-its-own>),
  [B-GUIDE-3](<Decisions/Layout and geometry/Alignment guides outside their view (GUIDE).md#b-guide-3-one-child-whose-guide-would-put-it-outside-its-region-is-held-inside-it>). **Recorded**; the guide placements were
  closed by the owner's 2026-10-12 ruling ("try to support it"), and content
  drawn at its own size in a frame, an overlay or a background on 2026-10-18
  ([B-GUIDE3-1](<Decisions/Layout and geometry/Drawing past a region (GUIDE3).md#b-guide3-1-content-larger-than-its-frame-or-base-is-still-cut>));
  a stack or another container still cuts what overhangs it (B-GUIDE3-1-P3).
  The other exceptions are displaced drawing, L6,
  and a drop shadow, which is drawn past its view the same way, at the view's
  place in the stacking order (since 2026-10-18, C6).

### L6. Displaced drawing hides what it passes over

- **SwiftUI:** `.offset` and `.position` draw the view at its new place in the
  normal stacking order, with whatever is behind showing through where it
  was and between its glyphs (not measured; Apple's documentation of
  `clipped(antialiased:)`).
- **TUIkit:** the same stacking order since 2026-10-18 — over the views before
  it, under the views after it, clicked where it is drawn, with nothing
  painted where it was laid out and the blank cells at either end of each line
  left out — and so is a spring transition's overshoot (since 2026-10-12).
  Blanks INSIDE a line still paint: a `Spacer` between two labels of a
  displaced row covers what is under the gap. While a view is arriving in a
  transition, its slot clips it.
- **Why:** a cell holds one glyph and has no transparency, so being over a
  neighbour means erasing it.
- **Decided:** [§2.9](<SwiftUI compatibility guide.md#29-what-clips-a-floating-layer-and-how-far-a-spring-may-carry-a-view>),
  [B-GUIDE3-4](<Decisions/Layout and geometry/Drawing past a region (GUIDE3).md#b-guide3-4-offset-and-position-still-float-over-the-views-after-them>).
  **Medium.**

### L7. Lazy containers window what they draw; they do not defer creation

- **SwiftUI:** a lazy stack creates a row as it nears the screen and releases
  it a few updates after it leaves, estimates its own extent, and takes its
  cross-axis size from its first subview (Apple's `LazyVStack` documentation
  and WWDC26's "Dive into lazy stacks and scrolling").
- **TUIkit:** a lazy stack draws only the rows in its window: on its own, the
  rows that fit; as a `ScrollView`'s direct content, the visible viewport. A
  row out of the window keeps its state (see F1). The cross-axis size hugs the
  widest row placed. A lazy stack nested below other scroll content is not
  windowed. `LazyVGrid` and `LazyHGrid` measure every subview. `List` is the
  container built to scale.
- **Why:** TUIkit rebuilds the tree each frame and keeps no view objects, so
  for it creating a view is drawing it. The widest placed row is a steadier
  width than the first row's.
- **Decided:** [§2.8](<SwiftUI compatibility guide.md#28-lazy-stacks-window-the-render-list-is-the-scalable-container>),
  [LazyGrids.swift](../../Sources/TUIkitGrid/Views/LazyGrids.swift#L246-L249).
  **Recorded.**

### L8. A lazy stack lays its sections out whole

- **SwiftUI:** a stack lays out a `Section`'s header, rows and footer as its
  own children, and a modifier on the section applies to each part (the
  grid's case measured, B70; the rest not measured).
- **TUIkit:** a lazy stack keeps its own sections whole when it pins, and a
  `ForEach`'s sections whole when it does not. A modifier on such a section
  wraps it once: `.padding(.top, 10)` pads above its header only. A centred
  view in one can land a cell from where the stack would centre it. A sectioned
  `LazyVGrid` fills the width it is offered, where a grid of fixed columns
  otherwise hugs them.
- **Why:** pinning needs the section to know which lines are its header, and
  windowing by section keeps a long stack's cost to what it draws.
- **Decided:** [B-D1S-1](<Decisions/Layout and geometry/Sections and subview counting in stacks and loops (D1S).md#b-d1s-1-a-lazy-stack-keeps-its-own-sections-whole-all-of-them-pinned-a-loops-unpinned>), [B70](<Decisions/SwiftUI API completion decisions.md#b70-a-sectioned-lazyvgrid-is-a-stack-of-sections-each-around-a-grid-of-its-views>). **Lane.**

### L9. Some shapes of content count as one child

- **SwiftUI:** an `if` without `else` that is false is no child; an `AnyView`
  around several views is several children; a view of the app's own whose
  body is several views is taken apart even when it is modified or its body is
  an `if`/`else`, and the modifier applies to each part (measured, D1S
  probes).
- **TUIkit:** an `if` without `else` that is a `ForEach` row's only view is one
  child, empty while false; an `AnyView` that is a `ForEach` row is one child;
  a modified view of the app's own, or one whose body is an `AnyView` or an
  effect on several views, is one child (a body that is an `if`/`else` or a
  modifier on several views is taken apart since 2026-10-19, decisions
  [B-LAYOUT-8](<Decisions/Layout and geometry/Layout parity (LAYOUT).md#b-layout-8-a-body-that-is-an-ifelse-or-a-modifier-on-several-views-is-those-views-a-modifier-on-such-a-view-is-still-one-child>)). A stack neither draws
  nor spaces an empty child, so only an app's own `Layout`, which counts
  subviews, sees the first difference.
- **Why:** counting these exactly means building every row on every walk,
  which costs a lazy stack its window and a loop its row memo.
- **Decided:** [B-D1S-3](<Decisions/Layout and geometry/Sections and subview counting in stacks and loops (D1S).md#b-d1s-3-an-anyview-that-is-a-loops-row-is-one-child>), [B-D1S-5](<Decisions/Layout and geometry/Sections and subview counting in stacks and loops (D1S).md#b-d1s-5-a-loop-whose-rows-vary-is-built-to-be-counted>),
  [B-D1S-6](<Decisions/Layout and geometry/Sections and subview counting in stacks and loops (D1S).md#b-d1s-6-a-modified-view-of-the-apps-own-or-one-whose-body-is-an-ifelse-is-one-child>). **Lane.**

### L10. `safeAreaInset` puts the bar beside the view; there is no safe area

- **SwiftUI:** `safeAreaInset` lays the bar beside the view and also grows the
  view's safe area, so a `ScrollView` runs under the bar, a background extends
  beneath it, and `ignoresSafeArea()` reaches into it (measured, W05).
- **TUIkit:** only the first half. A scroll view stops at the bar, and a
  `List` or `TextEditor` under `safeAreaPadding` is padded whole rather than
  having its rows inset. `ignoresSafeArea` and `GeometryProxy.safeAreaInsets`
  do not compile.
- **Why:** in a cell grid the difference shows only as colour under the bar's
  blank cells, and a real safe area costs a field on the layout's hot path
  and a parity risk at every container.
- **Decided:** [B6](<Decisions/SwiftUI API completion decisions.md#b6-safeareainset-puts-the-bar-beside-the-view-there-is-no-safe-area>), [B25](<Decisions/SwiftUI API completion decisions.md#b25-safeareapadding-is-padding-or-a-scroll-views-content-margin>). **Owner** (2026-10-12: not
  convinced; do not build the safe area).

### L11. A border moves a guide by its ring, and a few wrappers stop one

- **SwiftUI:** `.alignmentGuide` passes out through every single-child
  modifier written after it, each translating it by where it put its content;
  `.border` strokes inside the view and moves nothing, so a leading guide of 5
  under `.border(_:width: 2)` still reports 5 (measured 2026-10-18,
  `Tools/SwiftUIProbes/Alignment guides/layout1.out`, case B).
- **TUIkit:** the same through `.padding`, `.frame`, `.position`, `.offset`,
  `.overlay`, `.background` and every wrapper that keeps its content's
  geometry, `.badge` among them (`AlignmentGuideWrapperTests`; SwiftUI's
  `.badge` passes it too, `badge.out`): `.onTapGesture`, `.tint`,
  `.onAppear`, and an environment write, whose content is asked in the
  context the write lays it out in, so a guide under `.lineLimit(1)` is found
  where the limited content draws it. `.border()` moves the guide in by
  its ring — a line and a blank cell across, a line down — and a
  `.toolbar`, a list row's insets or colours and a `BufferModifier` of the
  app's own that does not state `_keepsContentGeometry` stop it.
  `layoutValue(key:value:)` and `layoutPriority(_:)` are read through every
  single-content wrapper but the ones that lay their content out anew
  (`.padding`, `.frame`, `.position`, `.fixedSize()`), as SwiftUI loses a
  priority there (`Tools/SwiftUIProbes/Layout priority/priority.out`).
- **Why:** a terminal border takes cells round its content, so the content's
  guide is where the content is, inside the ring; and a guide is a closure
  evaluated against the dimensions its view laid out at, so a wrapper that
  moves its content without saying by how much would report a position from
  the wrong coordinate space. A wrong position is worse than a documented
  stop.
- **Decided:** [SA-L11](<Decisions/Layout and geometry/Layout parity (LAYOUT).md#b-layout-3-a-border-moves-a-guide-by-its-ring-and-a-few-wrappers-stop-one>).
  **Lane.**

### L13. A guide pushes a view at most 2^20 cells, and a runaway guide is reported

- **SwiftUI:** uses a finite guide as given at any magnitude: a guide of `1e300`
  places its view that far along, without a word, and its width is lost to
  rounding. A guide of `+∞` or NaN stops the app ("view origin is invalid") in
  every placement tried; one of `-∞` does not stop it, but places the view
  nowhere a layout can use: at the root, its x is infinite and its width NaN
  (measured 2026-10-12 at the root only, decisions B-GUIDE-2).
- **TUIkit:** one guide pushes a view at most 1,048,576 cells along its
  container (`AlignmentGuideRun.maximumPush`), or as far as the container's
  extent or its widest view if that is further; the `TUIKIT_MAX_ALIGNMENT_PUSH`
  environment variable raises it, up to 2^30. A push past it, and a guide that
  is not a finite number (NaN, `+∞` or `-∞`) on a view with a width and a
  height, is a logic error,
  reported through `SoftTrap` (an assertion in a debug build, once in a release
  build), and the view is placed as if its guide were at its own origin. On a
  view with no width or no height a guide that is not a number takes that
  place silently (`AlignmentGuideTests`).
- **Why:** no layout is a million cells along; such a guide is a runaway
  expression. Unbounded, a guide of `1e300` traps sizing a line, and a push of
  `1e7` or more builds a line that many cells long for each pushed row on every
  frame, and neither names the guide. `-∞` is reported with the other two:
  SwiftUI does not stop on it, but what it places is no position either. A
  small terminal squeezes rows to nothing, where `d.width / d.height` is
  legitimately infinite.
- **Decided:** [B-GUIDE-2](<Decisions/Layout and geometry/Alignment guides outside their view (GUIDE).md#b-guide-2-one-guide-pushes-a-view-at-most-4096-cells-whatever-the-containers-extent--decided-220-and-a-push-past-it-reported>).
  **Owner** (2026-10-12: 2^20, a push past it reported, an environment
  variable to override it).

### L15. A fill larger than its space is cut to it

- **SwiftUI:** `aspectRatio(_:contentMode: .fill)` and `scaledToFill()` offer
  the view the smallest size of the ratio that covers what they are offered,
  and the view is that size, drawn past its frame unless `.clipped()` is
  written: a 2:1 colour filling a 200×200 frame is 400×200, centred
  (measured 2026-10-14, `PROBES-1014/aspect-ratio`).
- **TUIkit:** the view is offered the same size, and drawn in a frame of the
  space it was offered, centred, so it is cut to that space and takes no more
  in the layout (`_AspectRatioView`, `AspectRatioLayoutTests`).
- **Why:** a terminal has no outside to draw into: what lies past a view's
  space is another view's cells, and the layout around it was sized for the
  space, not the fill.
- **Decided:** the owner's ruling of 2026-10-14 (the semantic audit's item 32,
  option a: a real layout modifier). **Lane.**

### L16. Offered nothing, a frame's ideal height is not its height

- **SwiftUI:** a frame with an ideal height and no maximum, offered no
  height (under `.fixedSize()`), is exactly its ideal:
  `Text("x").frame(idealHeight: 3).fixedSize()` is three rows tall
  (measured 2026-10-18, `Tools/SwiftUIProbes/Alignment guides/layout1.out`,
  case D2). Offered a height, it is its content's.
- **TUIkit:** across, the same (`FrameIdealOfferedNothingTests`); down the
  column such a frame is its content's height even offered nothing.
- **Why:** a TUIkit stack asks every child its natural height by offering it
  none, so "offered no height" is that ask, not SwiftUI's unspecified
  proposal, and answering the ideal there would lay the frame out at its
  ideal in every column, where SwiftUI's stacks offer a height and get the
  content's. The width has a mark of its own for the true ask (the
  ideal-width probe, and `.fixedSize()`'s flag when it draws). A height mark
  would take another bit of the measure generation.
- **Decided:** [B-LAYOUT-6](<Decisions/Layout and geometry/Layout parity (LAYOUT).md#b-layout-6-a-frames-ideal-is-its-size-offered-nothing-across-not-down>).
  **Lane.**

---

## State and data flow

### S1. A dynamic property in an optional field is live

- **SwiftUI:** for `var p: MyProperty? = MyProperty()`, `update()` is never
  called, an `@Environment` inside reads its default, and nothing inside is
  bound (measured, macOS 15, decisions-DYNP cases 2 and 2b, and lane SKEY's
  probe). With a
  retroactive `extension Optional: DynamicProperty`, SwiftUI binds it and
  keeps its state across a `nil`.
- **TUIkit:** looks through the optional: the walk's plan names the field,
  and each body a `nil` check says whether a property is there (S2). The
  `@State` inside is bound, the `@Environment` resolved, `update()` run and
  what it changes written back, and the state survives a `nil` gap, as SwiftUI
  does with the conformance. A `weak` field is not updated, as in SwiftUI.
- **Why:** TUIkit does not copy a SwiftUI limitation without a very good
  reason, and this one looks incidental. It lets a property be present
  conditionally without moving it into a child view. The cost is portability
  the other way: code relying on it silently loses `update()` on SwiftUI.
- **Decided:** [A-DYNP-1](<Decisions/State and dynamic properties/DynamicProperty update write-back (DYNP).md#a-dynp-1-a-property-in-an-optional-field-tuikit-treats-it-as-present-swiftui-ignores-it--decided-keep-it>). **Owner** (2026-10-11 and
  2026-10-12: keep unless a concrete correctness reason appears).

### S2. Dynamic properties are planned from declared types, and reach further than SwiftUI's

- **SwiftUI:** finds a view type's dynamic properties once, from the declared
  types of its fields, and installs each at its field's offset in every copy
  of the view. Only fields declared as a `DynamicProperty` are looked into;
  classes get no fields (OpenSwiftUI's reconstruction; consistent with what
  was measured: a field declared as a plain class holding a property subclass
  is never updated, and a dead `unowned` field that is not a property is never
  read).
- **TUIkit:** plans each type once from its fields' declared types
  ([PropertyPlan.swift](../../Sources/TUIkitView/State/PropertyPlan.swift)), so
  a custom `Mirror` changes nothing, and a field that cannot hold a property
  is never read. It reaches further: into properties held in optionals (S1)
  and existentials (S3; a class-bound one held `weak` or `unowned` too),
  checked by value each body; into a property subclass
  in a field declared as a plain class, held strongly, `weak` or `unowned`, by
  its object's class each body
  ([B-DYNVFIX-1](<Decisions/State and dynamic properties/Finding dynamic properties from declared types (DYNVFIX).md#b-dynvfix-1-a-property-subclass-behind-a-plain-class-field-is-reached-through-its-objects-class-each-body-held-strongly-weak-or-unowned>));
  into the contents of class properties (held strongly, `unowned` or `weak`;
  S6); and into modifiers
  stored in fields, whose `@State` is bound and `@Environment` resolved but
  whose properties' `update()` runs only where the modifier is applied, once,
  as SwiftUI's does (measured, DYNP `op.out` vii-c2;
  [B-DYNVFIX-4](<Decisions/State and dynamic properties/Finding dynamic properties from declared types (DYNVFIX).md#b-dynvfix-4-a-stored-modifiers-properties-are-updated-only-where-the-modifier-is-applied>)).
- **Why:** the owner's ruling (2026-10-12): keep what TUIkit supports even
  where SwiftUI does not, and fix the bugs inside each reach rather than
  dropping it (session notes `DYNV/notes.md`, `DYNV2/notes.md`).
- **Decided:** [decisions-DYNVFIX](<Decisions/State and dynamic properties/Finding dynamic properties from declared types (DYNVFIX).md>).
  **Owner** (2026-10-12).

### S3. A property in an existential field is bound, per concrete type

- **SwiftUI:** never binds a property held in an `any DynamicProperty` or
  `Any` field (measured 2026-10-10: `Tools/SwiftUIProbes/Dynamic property discovery/notes.md`,
  cases (vii-a) and (vii-a2)).
- **TUIkit:** binds, resolves and updates it, whatever the field held on the
  first frame: the walk's plan names the field, and each body reads what it
  holds (S2). Its concrete type is in its state key: a new type starts at its
  defaults, and an earlier type that comes back while the view stays finds
  the state it left.
- **Why:** a property whose type changes at one view identity keeps the view's
  own state, which no workaround on SwiftUI keeps whole.
- **Decided:** [B-SKEY-1](<Decisions/State and dynamic properties/State keys inside a DynamicProperty (SKEY).md#b-skey-1-an-existential-propertys-new-type-starts-afresh-and-an-earlier-type-that-comes-back-finds-what-it-left>). **Owner** (2026-10-12: keep
  existential fields).

### S4. A binding to a collection's element outlives the element

- **SwiftUI:** an element binding forwards to the collection's subscript (not
  measured past the end).
- **TUIkit:** a read past the end answers with the value that was there, and a
  write past the end is dropped.
- **Why:** an element binding outlives the frame that made it; a row removed
  while a control still holds its binding must not trap.
- **Decided:** [§1](<SwiftUI compatibility guide.md#1-match>) (the State row: "deliberately not a plain
  forward"). **Recorded.**

### S5. A focused value read ahead of its publisher arrives a frame late

- **SwiftUI:** `@FocusedValue` readers are mostly `Commands` and toolbar
  items, updated outside the view graph (not measured).
- **TUIkit:** readers are views. One drawn before its publisher in the same
  walk shows a changed value one frame (about 17 ms) late; the run loop asks
  for that frame itself.
- **Why:** removing the late frame takes a second walk of every page that uses
  the API.
- **Decided:** [B34](<Decisions/SwiftUI API completion decisions.md#b34-a-focused-value-reader-drawn-ahead-of-its-publisher-catches-up-a-frame-later>). **Lane.**

### S6. What a class property holds is installed as the object's, and every view holding it is redrawn by its writes

- **SwiftUI:** runs a class property's `update()`, but installs nothing inside
  it: an `@State` there is a constant binding of its initial value, and an
  `@Environment` reads its default, each with a run-time warning (measured
  2026-10-10: `Tools/SwiftUIProbes/Dynamic property discovery/op.out`, case vii-f).
- **TUIkit:** installs what the object holds — held strongly, `unowned` or
  `weak` — as the object's
  ([PropertyWalk+Objects.swift](../../Sources/TUIkitView/State/PropertyWalk+Objects.swift)).
  Its `@State` is the object's own, which no view's key holds: two views
  showing one object read and write one state, no change of the views holding
  it moves or drops it, and a write redraws every view drawn holding it, one
  served from the memo included. An object made anew with each value of the
  one view holding it keeps that view's state from frame to frame, as a view
  value's `@State` does. Its ids are its own. Its `@Environment` is each
  holding view's while that view's body and what it built run, and at rest —
  in an action's closure — the first view's drawn holding it. Every holder
  walks it before its body, and its own `update()` runs there, as SwiftUI's
  does.
- **Why:** the owner's ruling (2026-10-12) keeps what TUIkit supported: a
  class wrapper made per view value, and `@Environment(Model.self)` inside
  one. Binding it per view, as before, sent one view's writes into another's
  state and read another's environment in its closures (DYNV bugs 3 and 4).
- **Left:** an environment-scoped action read through the object, such as
  `dismiss`, acts for the first view drawn holding it, so a sheet sharing its
  page's object and calling the object's `dismiss` calls the page's, and stays
  open; read it in the view instead. The `@State` in an enum's case inside
  a long-lived object is the case's payload's: setting the case anew starts it
  at its defaults, and a payload kept and put back brings its state back. And
  an object made on demand in a body and kept, first shown in the pass it was
  made in, is taken for one made with the view's value: after another such
  object at its place, it starts from that one's state, which that one takes
  back when it is shown again.
- **Decided:** [B-DYNVFIX-3](<Decisions/State and dynamic properties/Finding dynamic properties from declared types (DYNVFIX).md#b-dynvfix-3-what-a-class-property-holds-is-the-objects-every-view-drawn-holding-it-is-redrawn-by-its-writes-each-reads-its-own-environment-while-it-draws-and-an-object-made-with-a-view-value-keeps-its-views-state>). **Lane.**

### S7. A wrong-typed write through an `AnyHashable` projection is dropped and reported

- **SwiftUI:** `Binding<AnyHashable>(_:)` force-casts a written value to the
  base binding's type, so a value of any other type traps (measured
  2026-10-18: `AnyHashable(Int8(7))` written through a projection of a
  `Binding<Int>` fails its cast; probe `Tools/SwiftUIProbes/Small parity items (PARITYMISC)/binding_anyhashable.swift`).
- **TUIkit:** reports it through `SoftTrap`, which stops a debug build as
  SwiftUI's trap would; a release build drops the write and the base keeps its
  value
  ([Binding+AnyHashable.swift](../../Sources/TUIkitView/State/Binding+AnyHashable.swift),
  `BindingTests`).
- **Why:** a soft trap is the framework's answer to a programming error with a
  safe fallback: loud where the developer is looking, never a crash in someone's
  terminal. S4 drops a write past a collection's end for the same reason.
- **Decided:** [B-PARITYMISC-1](<Decisions/Small parity items (PARITYMISC).md#b-paritymisc-1-a-wrong-typed-write-through-an-anyhashable-projection-is-reported-and-dropped>). **Lane.**

---

## Environment

### E1. Two environment values are read-only constants

- **SwiftUI:** `\.layoutDirection` and `\.sidebarRowSize` are settable.
  Right-to-left mirrors every horizontal layout, and a sidebar row size
  resizes sidebar rows (Apple's documentation).
- **TUIkit:** always `.leftToRight` and `.medium`, and a write does not
  compile. `flipsForRightToLeftLayoutDirection(_:)` returns the view.
- **Why:** nothing would honour a write yet, and a write that is accepted and
  ignored is what rule 2 forbids.
- **Decided:** [B1](<Decisions/SwiftUI API completion decisions.md#b1-layoutdirection-is-read-only-always-left-to-right>), [B74](<Decisions/SwiftUI API completion decisions.md#b74-sidebarrowsize-is-read-only-always-medium>). **Lane** (2026-10-12: the
  owner still wants right-to-left, out of scope for now). `\.legibilityWeight`
  was a third, and is settable and honoured since 2026-10-13 ([B2](<Decisions/SwiftUI API completion decisions.md#b2-legibilityweight-is-settable-and-every-text-drawing-site-steps-its-weight>)).

### E2. Reduce motion holds TUIkit's own spatial animations still

- **SwiftUI:** `\.accessibilityReduceMotion` reports the system's Reduce
  Motion setting, and the app decides what to change (Apple's documentation;
  not measured).
- **TUIkit:** under it, an animated change of `.offset`, `.position`, padding
  or a fixed `.frame`, a visual effect's offset, a shadow's offset, an
  `.animated` scroll transition's offset and a drag preview's flight jump to
  their end. Fades, colours, a shadow's radius, the focus breath, spinners and
  progress still animate. An app's own
  `Animatable` values are left to the app, as in SwiftUI. The value comes from
  the user's `TUIKIT_REDUCE_MOTION`, the app's TUI-only
  `Scene.reduceMotion(_:)`, or the system setting only where TUIkit is sure
  the user is at this machine (refusal review O1, 2026-10-14): the machine an
  app runs on need not be the one its user sits at
  ([ReduceMotion.swift](../../Sources/TUIkitApp/Environment/ReduceMotion.swift#L4-L9)).
- **Why:** the owner's reading: motion means movement in x and y, and the
  framework's own movement should honour the setting.
- **Decided:** [A-D3M-1](<Decisions/Presentation and windows/Dialogs, image sizes, format styles and reduce motion (D3M).md#a-d3m-1-what-else-reduce-motion-should-hold-still--decided-2026-10-05>), [C-FU2-1](<Decisions/Follow-ups on reduce motion, localisation and scrolling (FU2).md#c-fu2-1-reduce-motion-does-not-hold-still-an-apps-own-animations>).
  **Owner** (2026-10-05).

### E5. The display preferences come from the user's variables, and from the host only where it is local

- **SwiftUI:** `\.accessibilityReduceTransparency`,
  `\.accessibilityDifferentiateWithoutColor` and `\.colorSchemeContrast`
  report the system's settings, and the system's controls change with them
  (Apple's documentation; not measured).
- **TUIkit:** each is set by the user's `TUIKIT_REDUCE_TRANSPARENCY=1`,
  `TUIKIT_DIFFERENTIATE_WITHOUT_COLOR=1` or `TUIKIT_INCREASE_CONTRAST=1`, or
  by the host's setting only where TUIkit is sure the user is at this machine,
  as reduce motion is (E2): macOS's Reduce transparency, Differentiate without
  colour and Increase contrast, and GNOME's high contrast (GNOME has no
  setting for the other two). Reduce transparency draws every material and
  glass opaque. TUIkit's own drawing does not change for increased contrast
  (its palettes keep their contrast floors either way) or for differentiate
  without colour (its own non-colour cues are to be designed apart, under the
  focus colour rules); both are reported for the app's views to read. The
  values are read-only, and SwiftUI's underscored setters write them.
- **Why:** the machine an app runs on need not be the one its user sits at,
  so a host setting counts only with positive evidence (refusal review O1).
- **Decided:** owner ruling P5 (c), 2026-10-23
  ([VISUALS](<Decisions/Shapes, effects and animation/Visual effects rulings (VISUALS).md#p5-reduce-transparency-differentiate-without-colour-and-increase-contrast-are-read-as-reduce-motion-is>)).
  **Owner.**

### E4. A key a locale's language lacks reads English, not the key

- **SwiftUI:** a `Text` under `.environment(\.locale, _)` reads its key in
  that locale's language only: where the language's table lacks the key it
  shows the key itself; where the app has no table in that language at all it
  reads the development language's (measured 2026-10-18, macOS 15, an app
  bundle with `en`, `de` and `fr` tables; probe `Tools/SwiftUIProbes/Small parity items (PARITYMISC)/locale/`).
- **TUIkit:** reads it in that language and then in English, every place in
  turn, as it reads every key — so a key the German table lacks reads its
  English words under a German locale rather than `greeting.title`
  (`LocalizationService.reading(_:swiftUIKey:tableName:bundle:in:)`,
  `LocaleStringLanguageTests`).
- **Why:** TUIkit keeps the fallback every one of its lookups has, rather than
  copying a limitation: a missing translation shows the text it stands in for.
- **Decided:** [B-PARITYMISC-5](<Decisions/Small parity items (PARITYMISC).md#b-paritymisc-5-a-locale-override-re-reads-a-texts-key-not-a-buttons-title>). **Lane.**

---

## Focus and input

### I1. ⌘ shortcuts bind to a stand-in modifier

- **SwiftUI:** `.keyboardShortcut("s")` is ⌘S; `onCopyCommand` and its
  siblings answer ⌘C, ⌘X and ⌘V (the SDK's declarations and Apple's
  documentation).
- **TUIkit:** no terminal reports ⌘ on a key in its legacy encodings, so the
  default `.command` is remapped when the shortcut registers, to whatever the
  TUI-only `.commandKey(_:)` names: Control by default, or Option, a bare key,
  or nothing. Under the kitty keyboard protocol a ⌘ chord the terminal passes
  on is delivered with `.command`, as SwiftUI's, but only to `onKeyPress` and
  to shortcuts: a shortcut fires on a real ⌘ only where the app asks
  (`.keyboardShortcutsMatchCommand()`), and on its stand-in always.
- **Why:** a terminal keeps some ⌘ chords for itself (⌘C, ⌘V and ⌘Q nearly
  always, more on some), so a shortcut on a real ⌘ would work on one terminal
  and not the next; the stand-in works on all of them. And delivered to what
  matches a bare key, ⌘K would type a `k` into a field and fire every bare-`k`
  binding.
- **Decided:** [§4a](<SwiftUI compatibility guide.md#4a-swiftui-has-it--tuikit-should-add-it>) (the `.keyboardShortcut` row),
  [Terminal compatibility survey.md](<../Terminals/Terminal compatibility survey.md#command-is-never-reported>),
  [B-D1K-1](<Decisions/Input, clipboard and text editing/Kitty keyboard protocol, key-press phases and UndoManager (D1K).md#b-d1k-1-under-the-kitty-keyboard-protocol-a--chord-is-delivered-to-onkeypress-and-to-shortcuts-on-request>). **Medium.**

### I2. Shift on a typed character is the character's case

- **SwiftUI:** on macOS `KeyPress.modifiers` has Shift for `!` (not
  measured).
- **TUIkit:** a key that typed a character has Shift only when the character is
  uppercase: `A` has it; `!`, `+` and `_` do not, on every terminal and under
  the kitty protocol too. A shortcut's Shift is read from case. A key the
  terminal composed arrives composed (Option-A as `å` without Option as Meta).
- **Why:** the legacy encodings send only the character. One rule makes an
  event the same on every terminal.
- **Decided:** [§1](<SwiftUI compatibility guide.md#1-match>) (the Key presses row),
  [Terminal compatibility survey.md](<../Terminals/Terminal compatibility survey.md>). **Medium.**

### I3. Unbound Ctrl-H, I, J, M and [ act as Backspace, Tab, Return and Escape

- **SwiftUI:** on macOS these chords are mostly inert (the text system binds
  ⌃H to delete backward; not measured).
- **TUIkit:** under the kitty protocol, where they arrive as themselves, a
  chord nothing binds goes round once more as its legacy key. A binding on it
  still wins.
- **Why:** on every legacy terminal they are those keys, and users' habits are
  built on that.
- **Decided:** [B-D1K-3](<Decisions/Input, clipboard and text editing/Kitty keyboard protocol, key-press phases and UndoManager (D1K).md#b-d1k-3-ctrl-h-i-j-m-and--fall-back-to-their-legacy-keys-when-nothing-binds-them>). **Lane.**

### I4. `.focusable(false)` covers a subtree, and is additive

- **SwiftUI:** `.focusable(false)` speaks for one view: on a `VStack` it leaves
  the buttons inside focusable (Apple's documentation, per semantic audit
  item 29; not measured).
- **TUIkit:** it reaches every control in the subtree, and an inner
  `.focusable(true)` does not reopen a subtree an ancestor closed. A click
  still activates.
- **Why:** a TUIkit modifier wraps a subtree. Additive is what stops a Tab
  stop appearing with nothing drawn behind it.
- **Decided:** [§4a](<SwiftUI compatibility guide.md#4a-swiftui-has-it--tuikit-should-add-it>) (the Common modifiers row),
  [FocusableModifier.swift](../../Sources/TUIkitFoundation/Modifiers/FocusableModifier.swift#L37-L43).
  **Recorded.**

### I5. The first control takes the focus by itself

- **SwiftUI:** `prefersDefaultFocus(_:in:)` applies "when no other view has
  focus" (Apple's documentation; its examples are tvOS's, and macOS was not
  measurable offscreen).
- **TUIkit:** a screen or a newly presented sheet focuses its first control by
  itself. That automatic choice does not count as a view having the focus
  until something happens to it: the user moves the focus, clicks or scrolls
  it, or presses a key while it holds the focus, or the app or `.defaultFocus`
  moves it. Until
  then a preferred default takes over from it, on whichever frame its scope
  appears (pinned by `takesTheUntouchedAutomaticFocus`, `doesNotSteal` and
  `declinedKeyEndsTheAutomaticChoice`). A focus the user, an `@FocusState`
  write or `.defaultFocus` placed is never taken.
- **Why:** a keyboard interface needs somewhere to start.
- **Decided:** [B35](<Decisions/SwiftUI API completion decisions.md#b35-what-when-no-other-view-has-focus-means-for-a-preferred-default>), [§4a](<SwiftUI compatibility guide.md#4a-swiftui-has-it--tuikit-should-add-it>) (the `@FocusState` row
  states the rule). **Owner** (2026-10-12: an explicit focus overrides the
  default, and the automatic choice must not count as held; shipped
  2026-10-13).

### I6. Undo keys are Control chords, and TUIkit's own undo manager raises nothing

- **SwiftUI:** undo is ⌘Z, and `NSUndoManager` raises on an unbalanced group
  (the raise measured on macOS 15, B-D1K-5).
- **TUIkit:** a text control coalesces a typing run into one undo step, as
  the macOS text system does (measured on macOS 15.8, B-D1K-6; until
  2026-10-18 each input event's edits were one step). The keys are data: undo on
  Ctrl-Z, Ctrl-minus and Ctrl-/; redo on Ctrl-Y (a text control's yank while
  one has the focus), Ctrl-Shift-Z, Ctrl-_ and Option-_,
  replaced app-wide with `.undoShortcuts(_:)`. A `SecureField` registers
  nothing. Where Foundation has no `UndoManager` (Linux), TUIkit's own does
  nothing, or makes a step of its own, where `NSUndoManager` raises, and posts
  no notifications.
- **Why:** a terminal app that raised would die holding the terminal in raw
  mode. Ctrl-Z is the key a terminal user reaches for.
- **Decided:** [B-D1K-5](<Decisions/Input, clipboard and text editing/Kitty keyboard protocol, key-press phases and UndoManager (D1K).md#b-d1k-5-undomanager-on-linux-is-tuikits-own-without-notifications-or-selectors>), [B-D1K-6](<Decisions/Input, clipboard and text editing/Kitty keyboard protocol, key-press phases and UndoManager (D1K).md#b-d1k-6-a-text-controls-undo-steps-are-per-event-they-last-as-long-as-the-control-and-a-secure-field-has-none>),
  [B-D1K-7](<Decisions/Input, clipboard and text editing/Kitty keyboard protocol, key-press phases and UndoManager (D1K).md#b-d1k-7-the-undo-and-redo-keys-are-data-ctrl-z-among-them-redos-reach-only-some-terminals-and-the-status-bar-is-the-route-everywhere>). **Owner** for Ctrl-Z (2026-10-04); **Lane** for the
  rest.

### I7. Clipboard commands and shortcut localization

- **SwiftUI:** `onCopyCommand`, `onCutCommand` and `onPasteCommand` move item
  providers of any type; `KeyboardShortcut.Localization.automatic` remaps a
  shortcut for the keyboard layout and mirrors it right-to-left (Apple's
  documentation, B8).
- **TUIkit:** the commands exist on Apple platforms only (gated on
  `UniformTypeIdentifiers`, so they fail to compile on Linux rather than do
  nothing). Where the terminal speaks OSC 5522 (`TerminalClient.mimeClipboard`)
  they carry any type, as SwiftUI's do: a copy writes every representation its
  items register that has a MIME type beside their text, and a paste reads every
  type the clipboard holds that the focused view's paste commands accept, by
  `UTType` conformance. Elsewhere they carry text: a copy writes every item that
  loads as a string, one per line (a copy of no text at all copies nothing), and
  a paste offers the clipboard's text, triggering only for a type that accepts
  text. A copy goes to the terminal's clipboard by OSC 52
  where the terminal writes it, or to this machine's only when the user is
  provably at this machine, and otherwise says in the status bar that nothing
  was copied
  ([ClipboardWriter.swift](../../Sources/TUIkitFoundation/App/ClipboardWriter.swift#L65-L76));
  a paste is the terminal's bracketed paste, the app's own last copy or the
  local helper, never an OSC 52 read. SwiftUI's own `copyable`, `cuttable`,
  `pasteDestination` and `PasteButton` need no item providers and carry text
  on Linux too, so no TUIkit-only spelling is needed. Windows needs Win32
  arms of the system clipboard (CONTRIBUTING.md). Every `Localization` behaves
  as `.custom`: AppKit's remap for the keyboard layout is compiled code that
  cannot be copied, and needs to know what the user's layout can type, which a
  terminal does not say; mirroring (five pairs, documented in `NSMenuItem.h`)
  is [slated](#slated-to-change) to follow right-to-left.
- **Why:** a terminal's clipboard holds one string, and a terminal reports the
  character typed, not the key's place on the keyboard.
- **Decided:** [B8](<Decisions/SwiftUI API completion decisions.md#b8-keyboardshortcutlocalization-is-recorded-and-every-strategy-behaves-as-custom>); decisions B9, answered on 2026-10-12 (the
  owner asked whether OSC 52 was in the path, and what portable versions would
  take) and removed, since nothing was left to build. **Medium.**

### I8. A control takes the press once the gestures ahead of it give up

- **SwiftUI:** a plain-style button fails when its press is released off it, and
  a drag attached to it then reports its end (measured, macOS 15.8, lane 17g's
  probes).
- **TUIkit:** a control is not a recognizer. It is given the press once every
  gesture ranked ahead of it has given up, and then owns it: a drag attached to
  a button never hears the press, and a control behind an undecided gesture
  draws its pressed state late (a double-tap gesture on a `List` row holds the
  row's selection back by the double-tap interval).
- **Why:** TUIkit's controls act on the press at once; making each a
  recognizer that can wait or fail is B89's fuller version.
- **Decided:** [B89](<Decisions/SwiftUI API completion decisions.md#b89-a-control-takes-the-press-once-the-gestures-ahead-of-it-give-up-it-cannot-wait>). **Lane** (the fuller version turns about
  fifteen controls into recognizers).

### I9. Gesture timing

- **SwiftUI:** a table row's double-click uses the system's interval, 0.5 s.
- **TUIkit:** a long press ends, and a multi-tap gives up, on the first frame at
  or past its deadline, counted from the event that armed it. A tap's next click counts if released within 0.35 s of
  the last release, as measured on SwiftUI; a list row's double-click counts
  presses within 400 ms. A
  drag's velocity is a least-squares fit of the last 100 ms of reports, as
  UIKit's pan recognizer fits them (SwiftUI's own estimator is unknown). A
  disabled view's gestures are given up at the disable, as on macOS, on the
  frame after the one that disabled it (B-F2-2, no longer a deviation).
- **Why:** the run loop checks deadlines at each frame's start, and each click
  interval follows its own macOS counterpart: a tap's the measured tap, a
  row's `NSTableView`'s (B92, B93).
- **Decided:** [B91](<Decisions/SwiftUI API completion decisions.md#b91-a-drags-velocity-is-an-average-of-the-report-to-report-speeds>), [B92](<Decisions/SwiftUI API completion decisions.md#b92-timed-recognizers-run-on-the-frame-clock>), [B93](<Decisions/SwiftUI API completion decisions.md#b93-two-double-click-windows-a-rows-and-a-taps>),
  [B-F2-1](<Decisions/Input, clipboard and text editing/Stdin test flake, lost taps and the quit chord (F2).md#b-f2-1-a-press-drained-before-the-frame-that-fails-a-double-tap-restarts-it>), [B-F2-2](<Decisions/Input, clipboard and text editing/Stdin test flake, lost taps and the quit chord (F2).md#b-f2-2-a-disabled-views-gestures-are-given-up-at-the-next-press-as-a-removed-views-are>). **Lane.**

### I10. Drag and drop stays inside the app

- **SwiftUI:** payloads are `Transferable` and can leave the app; a drop
  operation decides the pointer's badge and what the source is told;
  spring-loaded controls highlight while a drag waits over them, and after
  the user's spring-loading delay (Apple's documentation, B10 and B82).
- **TUIkit:** a payload needs no `Transferable` and never leaves the app. A
  drop's action gets a `DropInfo` carrying the cell and the modifiers held at
  release. `.copy`, `.move`, `.delete` and `.alias` all accept a drop; only
  `.cancel` and `.forbidden` refuse it. A one-cell badge on the preview, not
  the pointer, names the proposed operation: `+`, `↗` or `⊘`, and none for a
  move, a delete or a cancel. A drop session's `localSession` is
  never `nil`. A spring-loaded control activates after the user's
  spring-loading delay where the session is local, and half a second
  elsewhere (or `TUIKIT_SPRING_LOADING_DELAY`, or an app's
  `.springLoadingDelay(_:)`), drawn hovered while it waits and pressed as it
  fires, as macOS draws it.
- **Why:** there is no system pasteboard to drag through, CoreTransferable is
  Apple-only, and a terminal's mouse reports carry the modifiers through the
  whole drag.
- **Decided:** [B10](<Decisions/SwiftUI API completion decisions.md#b10-item-provider-drag-and-drop-stays-in-the-app-and-only-cancel-and-forbidden-change-a-drop>), [B82](<Decisions/SwiftUI API completion decisions.md#b82-spring-loading-a-paused-drag-activates-a-control-drawn-waiting-and-firing>), [B83](<Decisions/SwiftUI API completion decisions.md#b83-the-drag-and-drop-session-values-ship-nothing-hands-them-out-yet>),
  [DragAndDropSession.swift](../../Sources/TUIkitFoundation/Input/DragAndDropSession.swift#L16-L23).
  **Medium.**

### I11. A content shape is whole cells, and shapes only the frame it is written on

- **SwiftUI:** `contentShape(_:eoFill:)` makes a view hit-test against the
  shape's path, in points; each view is hit-tested against its own shape, so
  in `.contentShape(Circle()).padding().onTapGesture { … }` the gesture
  answers inside the circle only, the padding taking no hits (Apple's
  documentation; not measured).
- **TUIkit:** a content shape is the cells its shape covers at least half of,
  the rule a clip keeps a cell by ([C9](#c9-a-clip-shape-keeps-or-clears-whole-cells)).
  The view's own regions are cut to them, and so are those of the modifiers
  whose frame is the shape's — `.contentShape(Circle()).onTapGesture { … }`,
  a `Button` whose label it shapes; a modifier with a `.padding()` or a
  `.frame` between it and the shape has a frame of its own, and takes all of
  it. A `Rectangle` keeps the frame (`ContentShapeTests`).
- **Why:** a view's hit area is its frame here (refusal review P3), and the
  shape reaches the modifiers around it as markers in its buffer, at the
  frame's corners: a modifier laid out at another frame finds none of its own
  size. Hit-testing each view against its shape would change how every hit
  area is found, which the frame-as-hit-area rule does not ask for.
- **Decided:** [B-W1B-3](<Decisions/Shapes, effects and animation/What the shapes unblocked (W1B).md#b-w1b-3-a-content-shape-is-carried-to-the-modifiers-around-it-as-geometry-markers>). **Lane.**

---

## Text

### T1. Font styles are intensity, not size

- **SwiftUI:** `.font(.title)` draws larger type, `Font.system(size:)` names a
  size, and a `Font.Design` (`.serif`, `.monospaced`) picks a face (Apple's
  documentation).
- **TUIkit:** the eleven text styles map to three intensity tiers: bold
  (`largeTitle` to `headline`), normal (`subheadline`, `body`, `callout`) and
  faint (`footnote`, `caption`, `caption2`). A point size does not compile. A
  design is accepted and ignored: every cell is in the terminal's one face
  ([Font.swift](../../Sources/TUIkitFoundation/Styling/Font.swift#L164-L176)).
- **Why:** a terminal has one font size, but "this is a heading" survives as
  intensity, and semantic styles are everywhere in SwiftUI code.
- **Decided:** [Two rules](<SwiftUI compatibility guide.md#two-rules-that-decide-every-case>) (rule
  2's worked example). **Owner** (2026-08-15, the three-tier mapping).

### T2. A localized key goes on looking past a named table

- **SwiftUI:** `Text("greeting", tableName: "Onboarding")` shows `greeting`
  when that table lacks the key (A14; not measured).
- **TUIkit:** it goes on to the registered strings, `Localizable`, and then
  TUIkit's own strings. TUIkit's own words fall back to the app's
  `Localizable` only in a language TUIkit has no translation for. The user's
  languages are read up to and including the first one TUIkit ships, then
  English.
- **Why:** an app gets some strings rather than keys, and can borrow TUIkit's.
- **Decided:** [A14](<Decisions/Named colours, localisation lookup and the swift-syntax range (D6M).md#a14s-lookup-order--decided-2026-10-05>), [B-FU2-1](<Decisions/Follow-ups on reduce motion, localisation and scrolling (FU2).md#b-fu2-1-a-language-tuikit-does-not-ship-is-read-only-as-far-as-the-first-it-does>). **Owner**
  (2026-10-05).

### T3. Markdown in a `Text` key is TUIkit's own parse

- **SwiftUI:** Foundation's parser (B86 measured its quirks).
- **TUIkit:** `InlineMarkdown`, which agrees with Foundation on a 138-case table
  and 550,000 random strings but for two things: named character references
  beyond about 140 common ones are drawn as written, and link reference
  definitions are not consumed. Two more differences are in the drawing:
  `^[…](inflect: true)` is drawn without inflection, and a code span is plain
  text, every cell being monospaced already.
- **Why:** Foundation's Markdown parser is Darwin-only.
- **Decided:** [B86](<Decisions/SwiftUI API completion decisions.md#b86-tuikits-markdown-parse-is-its-own-with-two-known-differences>). **Medium.**

### T4. Links are underlined, and a link inside a `Text` is a Tab stop

- **SwiftUI:** a `Link` and a link in a `Text` are accent-coloured, not
  underlined; a link in a `Text` is clickable and opens through the
  environment's `OpenURLAction` (the colours measured on macOS 15.8, B85; the
  click from Apple's documentation), and macOS gives it no place in the Tab
  order by default (not measured).
- **TUIkit:** both are underlined (`.linkUnderline(false)` removes it). A link
  in a `Text` carries an OSC 8 hyperlink for the terminal to open, and is a
  control as a `Link` is: a Tab stop that breathes while focused, opened by
  Return or a click (or copied, under `.linkActivation(.copy)`) with its
  destination shown in a popover, and `Link`'s menu on Shift+F10 or a
  right-click. Under `.linkDisplay(.urlInParentheses)` or `.urlOnly` it writes
  its URL out instead and is no control, as a `Link` is not.
- **Why:** a terminal has no pointer affordance for a link, so the underline
  is what marks one; and a link only the pointer could open would break the
  no-mouse-only rule, so the keyboard reaches it the way it reaches every
  other control (the owner's ruling B85-KEYBOARD, 2026-10-23).
- **Decided:** [Link.swift](../../Sources/TUIkitFoundation/Views/Link.swift#L41-L44)
  (**Recorded**), [B85](<Decisions/SwiftUI API completion decisions.md#b85-a-link-in-a-text-is-drawn-and-hyperlinked-and-is-a-control>) (**Lane**).

### T5. A live text in help and in a tab's title is read once

- **SwiftUI:** a live `Text` or key stays live in a button's title, a text or
  secure field's placeholder and a table column's header, and is read once in
  a window's navigation title and an alert's title and message (measured,
  macOS 15.8, `Tools/SwiftUIProbes/Live titles (TEXTFMT)/`). Help, which
  shows only while the pointer rests, and a tab's title are not measured.
- **TUIkit:** live where SwiftUI's is measured live, and read once where it
  is measured read once, as SwiftUI does (owner ruling B51-LIVE, 2026-10-24).
  Help (`help(Text)` and a key) and a tab's title are read once, when built;
  so is TUIkit's own chrome (`Card`, `Panel`, `Dialog`, `AlertPanel`, the
  status bar), which has no SwiftUI meaning to match.
- **Why:** help is a string the tooltip and the focused control's hint draw in
  the chrome's style, and a tab's title is laid out as a chip from its string;
  keeping either live means carrying the clock into those, for behaviour
  SwiftUI's is not known to have.
- **Decided:** [B51](<Decisions/SwiftUI API completion decisions.md#b51-a-live-text-read-for-its-string-is-read-once-when-it-is-built>), [B51-LIVE in TEXTFMT](<Decisions/Input, clipboard and text editing/Typed interpolations, live titles and keeper passthroughs (TEXTFMT).md#b51-live-live-titles-where-swiftuis-are-live>). **Lane.**

### T6. Text selection selects what is drawn

- **SwiftUI:** `textSelection` defaults to `.disabled` (Apple's
  documentation), and a selection stays inside one `Text`, in a `Table` inside
  one cell (measured, macOS 15, B-D4X-7).
- **TUIkit:** with no modifier, a drag on the page's background, plain text or
  a scroll view's content selects; list and table rows keep their own meaning
  unless `.enabled`. A selection may cross from one `Text` into the next, and
  under a scope around a `Table` a row's crosses its columns; a cell's own
  `.textSelection(.enabled)` keeps to the cell, as macOS's does (2026-10-24). One begun inside a bordered container
  keeps to its interior, unless the app says `.textSelectionScope(.pane)` or the drag goes more than 3 rows or 6 columns outside it, which widens it to the scope the container sits in (A-TEXT2-1, an experiment). What is selected is the page, not the
  menus and popovers over it.
- **Why:** an app that reports the mouse takes the terminal's own selection
  away, and that selection reached any text.
- **Decided:** decisions A13 (**Owner**, shipped 2026-10-05 and removed from
  the decisions doc; its deferred parts are in
  [Future options](<../Future options.md#handing-the-mouse-to-the-terminal-a132>)),
  [B-D4X-6](<Decisions/Input, clipboard and text editing/Clipboard, screen selection and the wrapping editor (D4X).md#b-d4x-6-the-screen-selection-is-on-wherever-a-drag-does-nothing-else>), [B-D4X-7](<Decisions/Input, clipboard and text editing/Clipboard, screen selection and the wrapping editor (D4X).md#b-d4x-7-row-text-under-enabled-is-kept-to-the-row-not-to-the-cell>),
  [B-D4X-8](<Decisions/Input, clipboard and text editing/Clipboard, screen selection and the wrapping editor (D4X).md#b-d4x-8-what-is-selected-is-the-page-not-the-layers-over-it>) (**Lane**).

### T7. Text entry keys

- **SwiftUI:** a vertical `TextField` takes a newline from Option-Return
  (measured) and Ctrl-Return (U+2028); `TextEditor`'s find bar opens with ⌘F;
  a field can hold several selection ranges.
- **TUIkit:** a newline comes from Option-Return where the terminal sends
  Option as Meta, and from Ctrl-O everywhere; Ctrl-Return and Shift-Return
  submit. A vertical field wraps one cell short of its edge, keeping that cell
  for the caret. The find bar opens with Ctrl-F, as ⌘F does, and Ctrl-G finds
  the next match, bar up or not; Shift-Ctrl-G the previous only where the
  terminal tells Shift apart (the kitty protocol). Every match is tinted, the
  current one selected over it, and macOS's options (Ignore Case; Contains,
  Starts With, Full Word) are a row under its search field, a toggle and a
  button that steps through the three, rather than a menu. A field selects
  one range: an app's multiple selection selects its first. Ctrl-U kills
  from the caret to the start of its line in every text control, as
  readline's `unix-line-discard` does at a shell prompt — the whole text
  before the caret in a field on one line, the caret's logical line in a
  vertical field and a `TextEditor`, never its line break — as one undoable
  edit that Ctrl-Y yanks back (a `SecureField` keeps no kill). macOS binds
  no Ctrl-U (Cocoa's `StandardKeyBinding.dict`); ⌘⌫ deletes to the start of
  the line there.
- **Why:** what the terminal delivers. ⌘ is the terminal's, so ⌘F and ⌘G are
  Control chords, and the editor gives up Emacs Ctrl-F (Right arrow does the
  same) where it has a find bar; a field keeps it. A legacy terminal sends
  Shift-Ctrl-G as Ctrl-G. Ctrl-U is what a terminal user's fingers expect
  of any line they type into, and ⌘⌫ is the terminal's, as every ⌘ chord is. A menu of options would make the text editor's
  module depend on the menus' and the pickers'.
- **Decided:** [B62](<Decisions/SwiftUI API completion decisions.md#b62-a-vertical-textfield-is-a-text-field-that-wraps-not-an-editor-with-a-fields-chrome>), [B63](<Decisions/SwiftUI API completion decisions.md#b63-a-newline-from-the-keyboard-option-return-where-the-terminal-sends-it-ctrl-o-everywhere>), [B65](<Decisions/SwiftUI API completion decisions.md#b65-a-text-fields-selection-is-one-range>),
  [B81](<Decisions/SwiftUI API completion decisions.md#b81-the-find-bar-ctrl-f-opens-it-ctrl-g-finds-the-next-match-and-its-options-are-a-row>). **Medium**, with **Lane** choices of key.

### T8. `textContentType` filters what can be typed

- **SwiftUI:** `textContentType(_:)` is a hint for autofill (Apple's
  documentation).
- **TUIkit:** a terminal has no autofill, so the content type is an allowed
  character set: typed and pasted characters that no valid value holds are
  dropped, and the terminal's bell rings — once for a paste, however many it
  drops (`.oneTimeCode` takes digits only, `.emailAddress` letters, digits,
  `@`, `.` and the rest of RFC 5322's ``!#$%&'*+-/=?^_`{|}~``). Every
  `NSTextContentType` member is spelled; one whose values are free text (a
  name, an address part, `.dateTime`) filters nothing. A `TextEditor` filters
  as a field does, and a line break is a character like any other, refused
  where the type cannot hold one, as in a vertical field (2026-10-18,
  [B-PARITYMISC-2](<Decisions/Small parity items (PARITYMISC).md#b-paritymisc-2-every-nstextcontenttype-is-spelled-free-text-types-filter-nothing-and-a-texteditor-filters-as-a-field-does>)).
- **Why:** a terminal has no autofill, so the type was given a meaning a
  terminal can carry.
- **Decided:** [TextContentType.swift](../../Sources/TUIkitStyling/Styles/TextContentType.swift#L11-L17).
  **Owner** (2026-10-13): kept: "We should not accept invalid characters in
  an email address field", but not silently: a dropped character rings the
  terminal's bell, and each set admits every character a valid value holds.

### T9. A date field's order is fixed

- **SwiftUI:** a `DatePicker`'s fields follow the locale's order, and the
  `.graphical` style draws a clock for the time (not measured).
- **TUIkit:** the inline field is `YYYY-MM-DD HH:MM` whatever the locale
  (`\.locale` deliberately does not reorder it; the calendar and time zone do
  apply), and `.graphical` draws an hour-and-minute field under the month.
- **Why:** the typing model depends on the columns holding still under the
  caret.
- **Decided:** [DatePicker.swift](../../Sources/TUIkitPickers/Views/DatePicker.swift#L43-L55),
  [§4a](<SwiftUI compatibility guide.md#4a-swiftui-has-it--tuikit-should-add-it>). **Recorded.**

### T10. `Text`'s own `foregroundStyle` changes at once under an animation

- **SwiftUI:** a colour set inside `withAnimation` fades, whether it is set
  with `Text`'s own `foregroundStyle(_:) -> Text` or with the `View` modifier
  (not measured for `Text`'s; documented as animatable).
- **TUIkit:** the `View` modifier's colour fades, as `.background` and
  `.border` do; `Text`'s own overload keeps the colour in the view value, so
  nothing asks the animator and it changes at once
  (`ColorAnimationTests`). Wrap the text — `VStack { Text(…) }.foregroundStyle(…)`
  — to fade it.
- **Why:** fading it would put an animation-store lookup in every `Text`, the
  most-drawn view, every frame, for every app.
- **Decided:** WL-Q1 (settled by the owner's rulings, 2026-10-19): study it with
  A40's cheaper per-`Text` animation state, and adopt it only under the ~1%
  bar A40 set. **Medium**, until that study.

### T11. A floating-point number interpolated into a key is not padded to six digits

- **SwiftUI:** `Text("\(3.5)")` draws `3.500000`, and `Text("\(Float(3.25))")`
  `3.250000`: a number interpolated with no specifier is written through its
  printf conversion (`%lf`, `%f`) in the locale, whose precision is six
  fraction digits, trailing zeros and all (measured, macOS 15.8, 2026-10-24,
  `Tools/SwiftUIProbes/Interpolated values drawn (TEXTFMT)/`). An integer is
  grouped, `1,234,567`.
- **TUIkit:** the number is written in `\.locale` as `.number` writes it:
  grouped as SwiftUI's is, with the locale's separators, but a floating-point
  number has at most six fraction digits and **no trailing zeros** — `3.5`,
  `3,5` in `de`, `3.141593`, `0.3` for `0.1 + 0.2`; `∞` and `NaN` for `inf`
  and `nan` (`InterpolatedNumber`, `InterpolatedNumberTests`). The key is
  SwiftUI's (`%lf`), so translations match.
- **Why:** the owner: "I don't think we want to mimic things like turning
  "3.5" into "3.500000" because that's ugly and IMO a bug in SwiftUI." Six
  digits at most is `%lf`'s own precision, so a number reads as SwiftUI's
  with the padding taken off, not as the seventeen digits the shortest
  round-tripping form would write for `0.1 + 0.2`.
- **Decided:** [B-TEXTFMT-1](<Decisions/Input, clipboard and text editing/Typed interpolations, live titles and keeper passthroughs (TEXTFMT).md#b-textfmt-1-a-number-interpolated-without-a-specifier-is-drawn-in-the-locale-without-swiftuis-padding>).
  **Owner** (2026-10-24).

---

## Colour and drawing

### C1. A colour is a five-byte value

- **SwiftUI:** a named colour from an asset catalogue keeps its light and dark
  variants and chooses where it is drawn, whatever the variants are;
  extended-range components survive (Apple's documentation; not measured).
- **TUIkit:** a colour set's variants (and a dynamic `NSColor`'s, read under
  aqua and darkAqua) are kept as a two-byte place in a process-wide table of
  (light, dark) pairs and chosen where the colour is drawn, as in SwiftUI. The
  exceptions are chosen when the `Color` is made, by the default palette's
  colour scheme: two variants that differ in opacity (a `Color` has one alpha),
  a variant that is not plain RGB (a system-colour reference, a palette role, a
  pattern), and any new pair once the process has made 65,536 different ones. A
  colour's components are clamped to 8-bit sRGB when it is made (a
  `Color.Resolved` keeps the extended range).
- **Why:** `Color` is five bytes with no padding, carried by every `Text` and
  every cell run; there is room for a two-byte place in a table and one alpha,
  not for two colours.
- **Decided:** the owner's ruling B-D6M-1, option 3 (2026-10-24), built as
  [B-D6M-4](<Decisions/Named colours, localisation lookup and the swift-syntax range (D6M).md#b-d6m-4-an-asset-catalogue-colour-chooses-its-variant-where-it-is-drawn>);
  [§1](<SwiftUI compatibility guide.md#1-match>) (the Color values row). **Owner.**

### C2. A gradient is one or two samples a cell, corrected for the cell's shape

- **SwiftUI:** gradients and meshes are drawn per pixel; a `RadialGradient`'s
  radii are points (the SDK's declarations; B95 compared SwiftUI's mesh
  pictures with probes).
- **TUIkit:** each cell takes the colour at its centre, so a smooth ramp is a
  staircase on a glyph terminal (a terminal that takes pictures draws a
  gradient behind blank cells as a picture). Where the terminal draws Block
  Elements to the line's edges, a blank cell that a ramp changing down a
  column fills is two samples, `▄` in its bottom half's colour over its top
  half's: a gradient view, `.background(gradient)` behind the content's bare
  cells, and a rectangle-family shape's whole cells (since 2026-10-24, owner
  ruling B95). Apple Terminal, whose Block Elements fall short of the line,
  keeps one sample; so does a cell with a glyph, a translucent or blended
  ramp, and a terminal with no colour. Copying such a region gives `▄`, not
  spaces. A gradient filling a shape that is rasterized (C8) is sampled per
  half cell on every terminal, a step half a row tall, as the shape's edge is.
  `RadialGradient`'s radii are cells measured across, with the height derived
  through the cell's aspect so a circle looks like one; `AngularGradient`'s
  angles are corrected the same way. A mesh's patches are evaluated exactly
  where SwiftUI tessellates (a level or two of difference).
- **Why:** a cell shows at most two colours, split by a glyph; a cell is about
  twice as tall as it is wide, so radii and angles are corrected for a circle
  to look like one, and the second sample goes down the cell, where the
  resolution is coarse.
- **Decided:** [B95](<Decisions/SwiftUI API completion decisions.md#b95-a-mesh-is-one-sample-a-cell-on-a-glyph-terminal-and-a-picture-where-the-terminal-takes-one>),
  [§3, "Closed: `foregroundStyle`…"](<SwiftUI compatibility guide.md#closed-foregroundstyle-takes-some-shapestyle>),
  [AppearanceAndColors](../../Sources/TUIkit/TUIkit.docc/Articles/AppearanceAndColors.md#L237-L241).
  **Medium.**

### C3. `Text("a").foregroundStyle(.secondary)` is the palette's tier

- **SwiftUI:** the hierarchical level, derived from any foreground style above
  (Apple's documentation).
- **TUIkit:** on a `Text` it binds `Color`'s `.secondary`, the palette's
  secondary tier. On any other view `.secondary` is the level, as in SwiftUI.
- **Why:** `Text.foregroundStyle` returning `Text` takes only a `Color`, so that
  a gradient on one fragment of a concatenation fails to compile rather than
  being lost.
- **Decided:** [B22](<Decisions/SwiftUI API completion decisions.md#b22-the-content-levels-and-the-two--and-three-style-foregroundstyle>), [§3](<SwiftUI compatibility guide.md#closed-foregroundstyle-takes-some-shapestyle>). **Lane.**

### C4. Images size by cells, and are read once

- **SwiftUI:** an image that is not resizable is its natural size in points,
  overflowing its frame centred; a tiled image repeats at its natural size and
  cap insets are points; an `NSImage` drawn into after it is shown shows its
  new pixels; `Image(systemName:)` always draws its symbol (Apple's
  documentation; not measured).
- **TUIkit:** the natural size applies where the terminal's cell size in points
  is known (Apple Terminal, Warp, iTerm2, Ghostty on its own Mac); elsewhere
  an image fits what it is offered. A larger image is cut from its top-leading
  corner. Tiles and caps follow the same rule: at the natural size, with caps
  in points, where the cell's size is known (since 2026-10-19, B-D3M-3);
  elsewhere at the scale the whole image fits at. An image made from a `CGImage` or `NSImage` is read once and keeps
  its first pixels. `Image(systemName:)` draws nothing unless a font supplies
  the symbol's glyph (on a Mac, a terminal using SF Mono with the SF Symbols
  font installed).
- **Why:** a cell grid has no points unless the terminal says how big a cell
  is; noticing an in-place edit would mean hashing pixels every frame.
- **Decided:** [§2.4](<SwiftUI compatibility guide.md#24-image-is-textascii-sf-symbols-render-as-glyphs-in-narrow-circumstances>), [B-D3M-2](<Decisions/Presentation and windows/Dialogs, image sizes, format styles and reduce motion (D3M).md#b-d3m-2-an-images-natural-size-is-known-on-four-hosts-and-ghosttys-only-locally>),
  [B-D3M-3](<Decisions/Presentation and windows/Dialogs, image sizes, format styles and reduce motion (D3M).md#b-d3m-3-tiles-and-caps-follow-the-natural-size-and-caps-are-in-points>). **Medium**, with **Lane** choices.

### C5. A material drops the glyphs behind it and is a translucent surface

- **SwiftUI:** a `Material` blurs what is behind it and tints it, with
  vibrancy for the content on it; an inactive window's materials go flat
  (Apple's documentation; not measured).
- **TUIkit:** what a `Material` covers is frosted — its glyphs dropped,
  each cell keeping its own field — and a palette surface at a fraction of
  its opacity (`.ultraThin` 0.35 to `.ultraThick` 0.92; `.bar` the bars'
  surface at 0.8) is composited over that, cell by cell (since 2026-10-24,
  owner ruling O5-FROSTED, option (c); before, the glyphs behind stayed).
  The colours are not averaged with their neighbours. Over nothing but the
  page it is the tint. One that does not appear active is opaque
  (`Material.paint(in:)`; `MaterialTests`, `MaterialFrostTests`). Nothing
  of TUIkit's sets `\.backgroundMaterial`.
- **Why:** a cell has no sub-cell detail to blur, and a dropped glyph is what
  a blur does to a letter at that scale. Averaging each cell with its 5 × 3
  neighbourhood, option (b), was built and cost +66.4% on Stress
  `translucent --variant material` (owner's A/B, 15 reps), which the ruling
  counted significant (`Opacity as composition.md` §111).
- **Decided:** [O5](<Refusals re-examined, wave 17 (2026-10-03).md#o5-materials-and-glass-materialactiveappearance-plus-differentshape-material-w13s-material-backgroundmaterial-p14s-glass>),
  ruled 2026-10-12: option (b); the frost, [O5-FROSTED](<Decisions/Shapes, effects and animation/Visual effects rulings (VISUALS).md#o5-frosted-a-material-frosts-what-is-behind-it>),
  ruled 2026-10-23: (b), or (c) if (b)'s cost is significant; shipped as (c). **Medium**. Glass, the same surface with a rim, is
  [C11](#c11-glass-is-a-material-with-a-highlighted-rim-not-a-lens).

### C6. A shape draws within its frame

- **SwiftUI:** a stroke is centred on the shape's outline, so half of it lies
  outside the frame and is drawn there; an offset, rotated or scaled shape
  draws wherever its path goes (Apple's documentation; not measured).
- **TUIkit:** a shape draws only the cells of its frame. A rasterized stroke
  loses its outer half where the outline touches the frame — a stroked circle
  is thinner at its four extremes — and a moved shape is cut at the frame's
  edge. `strokeBorder(_:lineWidth:antialiased:)` draws the whole line, inside.
  A rectangle-family stroke drawn in lines sits in the outermost cells either
  way (`ShapeTests`).
- **Why:** a view's buffer is the size it reports ([L5](#l5-a-view-does-not-draw-outside-the-size-it-reports));
  drawing past it would mean a floating layer per shape.
- **Decided:** [B-W1-5](<Decisions/Shapes, effects and animation/Shapes (W1).md#b-w1-5-a-shape-draws-within-its-frame>). **Lane.**

### C7. A rectangle-family shape draws in the terminal's own glyphs

- **SwiftUI:** every shape is rasterized, its corners curved at the radius
  given and its strokes as wide as asked (Apple's documentation).
- **TUIkit:** `Rectangle`, `RoundedRectangle`, `UnevenRoundedRectangle`,
  `Capsule` and `ContainerRelativeShape`, stroked no wider than a column and
  undashed, are a box of light line glyphs — `┌` where a corner's radius is
  zero, `╭` where it is not, whatever the radius — in whatever `Appearance` is
  in force; `stroke` and `strokeBorder` draw the same box. Filled, their
  rounded corners are cut at quadrant resolution, by at least one quadrant
  however small the radius, and one row tall the ends are the caps `▐ ▌`; on
  Apple Terminal a corner is a whole cell. A single cell, every corner at
  once, is its coverage: a one-cell capsule is a block. `Rectangle().fill(s)`
  is `Color` as a view, byte for byte (`ShapeTests`, `ShapeRasterTests`).
- **Why:** these shapes' edges land on cell boundaries, and the glyphs are the
  medium's own drawing of them; a radius below half a cell has no other way to
  show, and a corner the caller rounded should look rounded.
- **Decided:** refusal review W1; [B-W1-2](<Decisions/Shapes, effects and animation/Shapes (W1).md#b-w1-2-a-rectangle-family-stroke-is-a-box-of-light-lines-whatever-the-appearance>),
  [B-W1-3](<Decisions/Shapes, effects and animation/Shapes (W1).md#b-w1-3-a-rectangle-family-fill-cuts-its-rounded-corners-in-quadrants>). **Lane.**

### C8. Every other shape is antialiased per half cell, and never a picture

- **SwiftUI:** a shape is rasterized per pixel and antialiased (Apple's
  documentation).
- **TUIkit:** a `Circle`, an `Ellipse`, a `Path`, a shape of the app's own and
  any transformed or trimmed shape is rasterized at half-cell resolution — a
  column across, half a row down — each half drawn at the share of it the shape
  covers, as alpha, composited over what is behind (`FillStyle(antialiased:
  false)` draws a half at least half covered, whole). It is cells on every
  terminal, including those that take pictures; with no colour, it is the
  half-block glyphs alone. A gradient or a mesh filling it is sampled at the
  same half cells (`ShapePainter`), so its ramp steps half a row at a time
  (C2). A dash pattern that would be walked more than
  65,536 lengths along a stroke — a dashed line to the edge of the plane —
  draws the line unbroken, where CoreGraphics walks every dash (0.13 s over
  10⁷ units, unfinished over 10⁹; measured); one shorter than a pixel draws
  unbroken in both (`ShapeRasterTests`).
- **Why:** a shape's picture always has transparent pixels, which a terminal
  composites against the cell it is placed in rather than against what TUIkit
  knows is behind it — the reason a translucent gradient declines the picture
  path too (`BackgroundModifier.pictured`).
- **Decided:** [B-W1-4](<Decisions/Shapes, effects and animation/Shapes (W1).md#b-w1-4-the-rasterizer-draws-half-blocks-at-their-coverage-and-no-shape-is-a-picture>). **Lane.**

### C9. A clip shape keeps or clears whole cells

- **SwiftUI:** `clipShape(_:style:)` clips the view's pixels to the shape,
  antialiased unless the fill style says not (Apple's documentation).
- **TUIkit:** a cell of the view is kept where the shape covers at least half
  of it and cleared to what is behind the view otherwise; the fill style's
  antialiasing does not apply. A `Rectangle` keeps the frame, as `clipped()`
  does (`ShapeModifierTests`).
- **Why:** a cell holds one glyph, so it is kept or not, by the ½ rule every
  glyph decision takes (`Opacity as composition.md` §6a).
- **Decided:** refusal review W1 ("rects clip to the frame; other shapes mask
  cells at coverage ≥ ½"), [B-W1-11](<Decisions/Shapes, effects and animation/Shapes (W1).md#b-w1-11-a-clip-keeps-a-cell-at-half-coverage-and-leaves-the-hit-area-alone>). **Lane.**

### C10. A shadow is whole cells, cast by the cells a view paints

- **SwiftUI:** `shadow(color:radius:x:y:)` and `ShadowStyle` blur, tint and
  offset a view's per-pixel alpha, the radius and the offsets in points (the
  SDK's declarations and Apple's documentation; not measured).
- **TUIkit:** they are whole cells. The shadow is cast by the cells the view
  paints — a glyph, or a cell with a field, reverse video or a line of its
  own — moved `x` columns and `y` rows, at the colour's alpha, and `radius` is
  an alpha falloff across that many cells beyond it, `1 / (radius + 1)` less a
  cell and rounded at the corners, up to a radius of 32 cells, past which it
  is drawn as 32. So a ported `radius: 8` is eight cells, as `.padding(8)` is,
  where SwiftUI's is eight points; and a label with no background casts the
  shape of its letters a whole cell at a time. What the
  shadow falls on keeps its glyphs, ink and field darkened together
  (`ShadowTests`, `ShadowFieldTests`). A shadowed style
  (`ShapeStyle.shadow(_:)`) is cast the same way from the cells drawn with
  the style alone — a shape's, a background's fill, a text's letters — at
  the style's own alpha, a ramp's at its representative colour's
  ([B-W1B-1](<Decisions/Shapes, effects and animation/What the shapes unblocked (W1B).md#b-w1b-1-a-styles-shadow-is-cast-by-whatever-draws-with-it-from-the-cells-it-drew>);
  `ShapeStyleShadowTests`).
- **Why:** a terminal addresses whole cells (U1), and the one alpha a cell has
  that matters to a shadow is whether the view paints it. The limit is cost: a
  shadow costs the square of its radius at every render and every frame
  ([B-O6-1](<Decisions/Shapes, effects and animation/Shadows (O6).md#b-o6-1-a-shadow-is-cast-by-the-cells-a-view-paints-and-falls-off-by-whole-rings>)).
- **Decided:** [O6](<Refusals re-examined, wave 17 (2026-10-03).md#o6-shadowstyle--w16-shadow-w13-shapestyleshadow--m>),
  ruled 2026-10-12: option (b), cells as-is, documented;
  [B-O6-1](<Decisions/Shapes, effects and animation/Shadows (O6).md#b-o6-1-a-shadow-is-cast-by-the-cells-a-view-paints-and-falls-off-by-whole-rings>). **Owner.**

### C11. Glass is a material with a highlighted rim, not a lens

- **SwiftUI:** `glassEffect(_:in:)` renders a shape behind the view filled
  with a physical glass material — it refracts, blurs and tints what is
  behind it, and lays its foreground effects over the view; interactive glass
  reacts to touches and the pointer (Apple's documentation and the macOS 26
  SDK's declarations; not measured — this Mac runs macOS 15).
- **TUIkit:** the shape is filled with a material's surface — `.regular` the
  regular material's (0.65 of the page's surface), `.clear` the ultra-thin
  one's (0.35), a tint that colour instead — composited cell by cell over what
  it covers, whose glyphs are dropped as under a material (C5), and rimmed: its outline drawn behind the view in the border's ink
  lifted (the tint's, tinted), in the lines of the appearance in force (a
  Braille outline, a solid band, or none under `.blank`). Glass that does not
  appear active is opaque, as a material is. Interactive glass lifts its rim
  again under the pointer; it takes no click and no focus. Layout is
  untouched, and the rim shows only in the view's blank cells — pad the view,
  as SwiftUI's examples do (`GlassEffectTests`). In a `GlassEffectContainer`,
  glass of one kind that touches, overlaps or comes closer than the spacing (in
  cells), or shares a union, is one shape — the rectangle round it — where
  SwiftUI's shapes blend by degrees (`GlassEffectContainerTests`); glass
  arriving there under an animation fades in, `.matchedGeometry` too, without
  SwiftUI's growing out of a nearby glass (`GlassEffectTransitionTests`).
- **Why:** a cell has nothing below it to bend, and its blur is a material's
  frost, the glyphs behind dropped (C5); a rim is what is
  left of glass's edge at cell resolution, and drawn in the appearance's lines
  it sits beside the app's boxes and buttons as one of them.
- **Decided:** [O5](<Refusals re-examined, wave 17 (2026-10-03).md#o5-materials-and-glass-materialactiveappearance-plus-differentshape-material-w13s-material-backgroundmaterial-p14s-glass>),
  ruled 2026-10-12: option (b) for Glass, with option (c)'s rim;
  [B-GLASS-1](<Decisions/Shapes, effects and animation/Glass (GLASS).md#b-glass-1-glass-is-a-materials-surface-with-a-highlighted-rim-behind-the-view>),
  [B-GLASS-2](<Decisions/Shapes, effects and animation/Glass (GLASS).md#b-glass-2-the-rim-is-drawn-in-the-appearances-family>),
  [B-GLASS-5](<Decisions/Shapes, effects and animation/Glass (GLASS).md#b-glass-5-a-container-draws-glass-that-comes-near-as-one-shape-round-all-of-it>),
  [B-GLASS-6](<Decisions/Shapes, effects and animation/Glass (GLASS).md#b-glass-6-glass-arriving-in-a-container-fades-in-an-id-keeps-a-glass-that-moves>). **Owner**, with **Lane** choices.

### C12. An image paint is one colour a cell, and its tile is a span of the fill where the cell's size is unknown

- **SwiftUI:** an `ImagePaint` repeats its region of the image at the
  region's size in points times the scale, from the top-leading corner of
  what is filled, or from the origin `in(_:)` names; its pixels are drawn,
  and an image is never late (measured on macOS 15.8,
  `Tools/SwiftUIProbes/Image paint/`).
- **TUIkit:** each cell is one colour, the mean of four samples of the
  picture, on every terminal: an image paint is never sent as a picture. A
  tile is its size in points over the terminal cell's
  (`\.imageCellPoints`); where the cell's size is not known (under tmux,
  over ssh to Ghostty) one tile spans what is filled, across, at the scale,
  and the tiling in points is lost. A picture that loads — a file, a URL —
  paints nothing until it has; a symbol, `Image(systemName:)`, has no pixels
  and paints nothing; a new picture shows at once under `withAnimation`
  (`ImagePaintTests`).
- **Why:** a cell holds one colour of field or ink; a picture of the tiles
  would sample the image a second time, at the terminal's pixels, and a
  terminal composites a picture against its own cell, not against what is
  behind it ([C8](#c8-every-other-shape-is-antialiased-per-half-cell-and-never-a-picture)).
  Without the cell's size there are no points to tile by ([C4](#c4-images-size-by-cells-and-are-read-once)).
- **Decided:** [B-W1B-4](<Decisions/Shapes, effects and animation/What the shapes unblocked (W1B).md#b-w1b-4-an-image-paint-is-sampled-cell-by-cell-and-paints-nothing-until-its-picture-is-there>). **Lane**, with **Medium** limits.
---

## Animation

### A1. A retargeted spring's duration does not blend, and `tracksVelocity` is read by nothing

- **SwiftUI:** a spring retargeted mid-flight hands its velocity to the next,
  blending the two springs' durations over `blendDuration`;
  `interpolatingSpring` and the other curves add overlapping animations;
  `Transaction.tracksVelocity` carries velocity forward (Apple's
  documentation).
- **TUIkit:** the velocity is handed on and overlapping animations add, as in
  SwiftUI (O3, 2026-10-18): a merging spring starts the next at the speed the
  value was moving, and any other animation runs beside the one it
  interrupts. The next spring takes its own duration at once, so
  `blendDuration` has nothing to blend; `tracksVelocity` is recorded and read
  by nothing.
- **Why:** each animation is a closed-form function of time from its start;
  a blend would make the curve depend on the one before it for as long as
  the blend lasts. TUIkit's own continuous controls, which `tracksVelocity`
  serves in SwiftUI, report a cell at a time and carry no velocity worth
  tracking.
- **Decided:** [B55](<Decisions/SwiftUI API completion decisions.md#b55-tracksvelocity-is-recorded-and-read-by-nothing-iscontinuous-is-set-by-tuikits-own-continuous-controls>), [B58](<Decisions/SwiftUI API completion decisions.md#b58-spring-is-swiftuis-numbers-two-quirks-kept-and-one-not>);
  the velocity and the adding were B58's lane, landed with O3. **Medium**.

### A2. Animation arithmetic follows the documentation where SwiftUI's answers do not

- **SwiftUI (measured):** `UnitCurve.linear` and the circular curves do not
  clamp out-of-range input; `circularEaseInOut.inverse` is the curve itself; a
  bounce at or below −1 is NaN; an overdamped spring's `velocity` is one more
  than the derivative of its `value`; a keyframe spring is evaluated backwards
  before its start; a zero-length keyframe is NaN.
- **TUIkit:** clamps, as `value(at:)` documents; answers the true inverse;
  stops a bounce at −0.999; answers the derivative; holds the start value
  before the start; arrives at once. Three other spring quirks are kept,
  because ported arithmetic reads them.
- **Why:** where SwiftUI's answer contradicts its own documentation, or is
  NaN, the documented answer is the one code can rely on.
- **Decided:** [B57](<Decisions/SwiftUI API completion decisions.md#b57-unitcurve-is-swiftuis-arithmetic-except-where-its-answers-contradict-its-documentation>), [B58](<Decisions/SwiftUI API completion decisions.md#b58-spring-is-swiftuis-numbers-two-quirks-kept-and-one-not>), [B60](<Decisions/SwiftUI API completion decisions.md#b60-keyframe-timelines-follow-swiftuis-curves-measured>).
  **Lane.**

### A3. Transitions move in whole cells, and a custom one is drawn by scrubbing

- **SwiftUI:** a transition interpolates its modifiers; `.scale` shrinks the
  view; `.blurReplace` blurs it as it scales between 0.9 and its size (measured,
  [`Tools/SwiftUIProbes/Transitions/tr4.out`](<../../Tools/SwiftUIProbes/Transitions/tr4.out>)); a removed view's content stays live; a transition may change the
  view's size and re-lay its siblings (Apple's documentation, B52); each part
  of a `combined` transition runs under its own animation (measured,
  [`Tools/SwiftUIProbes/Transitions/tr2.out`](<../../Tools/SwiftUIProbes/Transitions/tr2.out>) T12).
- **TUIkit:** `.move`, `.offset` and `.slide` move in whole cells; `.scale`
  uncovers the view from its anchor a cell at a time, and a scale above 1 draws
  the view whole. `.blurReplace` is that reveal from 0.9 of the view plus a
  fade, the blur drawn as the fade; `.upUp`, which grows as it leaves, leaves
  by the fade alone. A custom `Transition`'s body is drawn by rendering it at its
  end phase and at `.identity` and interpolating the values between; while a
  view leaves, its content is the picture it last drew, and the view keeps its
  `.identity` size throughout. The views around it glide as SwiftUI's do
  where A6 says. A `combined` transition plays as one effect under one
  animation for each half: the first part's own, or else the second's.
- **Why:** a frame is rebuilt from the tree, and a removed view no longer
  exists in it; a transition's parts share one presence, which a part with an
  animation of its own would split.
- **Decided:** [§2.9](<SwiftUI compatibility guide.md#29-what-clips-a-floating-layer-and-how-far-a-spring-may-carry-a-view>), [B52](<Decisions/SwiftUI API completion decisions.md#b52-a-custom-transitions-body-is-drawn-at-each-frames-point-between-its-phases>), [B54](<Decisions/SwiftUI API completion decisions.md#b54-a-scale-transition-uncovers-from-its-anchor-and-a-scale-above-1-draws-the-view-whole>),
  [B-TRANSITIONS2-4](<Decisions/Shapes, effects and animation/Transition follow-ups (TRANSITIONS2).md#b-transitions2-4-a-combined-transition-plays-under-one-animation-for-each-half>);
  [A34](<Decisions/Shapes, effects and animation/Visual effects rulings (VISUALS).md#a34-blurreplacetransition-is-its-scale-and-a-fade>);
  the size a custom body changes waits on [A-TRANSITIONS2-1](<Decisions/Shapes, effects and animation/Transition follow-ups (TRANSITIONS2).md#a-transitions2-1-b52-a-custom-transition-that-changes-its-views-size--lay-the-body-out-at-each-frames-size>).
  **Medium.**

### A4. A content transition is a dissolve in each text and image

- **SwiftUI:** each leaf reads `\.contentTransition` and animates its own
  content; `.interpolate` morphs matching glyphs, and `.numericText` rolls
  digits "in certain environments" (Apple's documentation, B61).
- **TUIkit:** each `Text` and raster `Image` reads it too (since 2026-10-24,
  owner ruling B61), so an inner `.contentTransition(.identity)` exempts its
  part; but what a leaf draws is a dissolve of its old cells into its new
  ones, whatever the transition: `.interpolate` keeps a cell whose character
  is the same and moves its colours, and `.numericText` and `.opacity`
  dissolve. A leaf takes its new size at once. The symbol-effect transitions
  are fades of the symbol.
- **Why:** a cell holds one glyph, so there is no glyph shape to morph or
  roll; the opacity compositor blends a cell's colours and hands its glyph
  over half way.
- **Decided:** [B61](<Decisions/SwiftUI API completion decisions.md#b61-a-content-transition-dissolves-each-text-and-image>), [§1](<SwiftUI compatibility guide.md#1-match>) (the Symbol effects row).
  **Lane.**

### A5. A text that changes under an animation snaps

- **SwiftUI:** with no `.contentTransition`, a `Text` whose string changes
  inside `withAnimation` cross-fades: the environment's default transition is
  none of `.identity`, `.opacity` and `.interpolate` (measured, A40).
- **TUIkit:** the change is drawn at once unless `.contentTransition(_:)` is
  written above it (A4).
- **Why:** a default dissolve makes every `Text` keep its last drawing in
  state, whether or not anything animates: measured on 2026-10-15 at up to
  +500% a frame (`fanout`), +69% on `textwall`, +13.5% on `menus`.
- **Decided:** [A40](<Decisions/SwiftUI API completion decisions.md#a40-should-a-content-change-dissolve-by-default-under-an-animation>). **Owner**: agreed on 2026-10-05 to dissolve
  by default if that cost under about 1%; measured far over it on
  2026-10-15, so a change is drawn at once.

### A6. Places glide in whole cells, and only in some containers; sizes change at once

- **SwiftUI (measured, macOS 15.8, 2026-10-17, `Tools/SwiftUIProbes/Insertion and removal (FB16)/FB16Probe.swift`
  with presentation frames every 0.5 s):** a change of layout takes effect at
  once, and under an animation every view whose frame changed glides to its
  new one — the view below an inserted row moved 187 → 194 → 202 → 218 →
  234 → 247 over an 8 s linear animation, for every transition, `.identity`
  included. A removed view plays its removal where it was, drawn beneath its
  siblings (its layer comes first in every removal sample), while they close
  up over it. Frames glide in points, sizes as well as positions, in every
  container.
- **TUIkit:** the children of an eager `VStack`, `HStack` and `ZStack` and
  the subviews of a `Layout` glide from their old places to their new ones,
  in whole cells, rounded half away from zero; a view leaving an eager stack
  or a `ZStack` gives its room back at once and is drawn where it was,
  beneath its siblings unless a `.zIndex` lifts it (`StackGlide`,
  `StackGlideTests`). A lazy stack, a `Grid`, a `List`'s and a `Table`'s rows
  move their children at once; there, in a `Layout` and where a `nil` is
  rendered on its own, a removal keeps its room while it plays and gives it
  back at once after. A container's own size — a border, a background, a
  frame — changes at once, so a border around a stack that has given a
  removal's room back is drawn at its new size while the view leaving is
  drawn past it. A child that comes to draw nothing — a stack whose only
  content has left — stands where it was while the change plays, and one
  that comes to draw something is placed directly, so the view leaving or
  arriving in it does not move with the gap the empty stack gives back
  (§3: a child with no extent takes no stack spacing); a removal animated
  longer than the change finishes at the stack's new place. A conditional
  drawn whole — a view's whole `body`, a modifier's content — draws a
  branch it leaves by a transition of its own over the branch it takes,
  past its frame, where SwiftUI draws it beneath (measured, [`Tools/SwiftUIProbes/Transitions/tr1.out`](<../../Tools/SwiftUIProbes/Transitions/tr1.out>) T8);
  one with none goes at once (A10).
- **Why:** a terminal draws whole cells; a glide is remembered per
  container (`PlacementStore`), and the containers that window their rows or
  lay out a lattice have not been given that memory yet. A size that glides
  would need a presented size for every view that draws around its content.
  Only a container composites a fade against what is beneath it; for two
  fades crossing, over and beneath are the same blend with the weights
  swapped.
- **Decided:** [decisions FB16](<Decisions/Shapes, effects and animation/Insertion and removal model (FB16).md>),
  B-FB16-1 to B-FB16-8, B-FB16-13, A-FB16-1;
  [B-TRANSITIONS2-2](<Decisions/Shapes, effects and animation/Transition follow-ups (TRANSITIONS2).md#b-transitions2-2-a-conditional-drawn-whole-draws-the-branch-it-leaves-over-the-one-it-takes>).
  **Owner** for the model (FB16 (a′), 2026-10-18); **Lane** for what stops
  short of it.

### A7. A frame draws every change since the last under one transaction, and an observed change takes the next scope's

- **SwiftUI (measured, macOS 15.8.1, 2026-10-18,
  `Tools/SwiftUIProbes/Transactions of observed changes/txn.out`):** a body
  reading two `@Observable` properties, one written plainly and one inside
  `withAnimation` in the same turn of the run loop, is updated once per
  write: unanimated for the plain one, animated for the other, in either
  order. An unanimated write followed by a `withAnimation` that writes
  nothing the body read, or nothing at all, is drawn unanimated, and that
  `withAnimation`'s completion runs as soon as its body returns, as Apple
  documents for a body whose changes create no animations.
- **TUIkit:** a frame draws every change made since the last one under one
  transaction (`AppState.consumePendingTransaction()`), so both writes are
  drawn animated; the animated write is, in either order
  (`ObservedChangeTransactionTests`). An unanimated observed change followed,
  in the same app's work before the frame, by a `withTransaction` scope that
  changed nothing any body read is drawn under that scope's transaction too
  (`AppState.transactionScopeEnded(_:)`), and the scope's completions go with
  its transaction: claimed for that frame, they run when the animation it
  draws the change with completes, not as the scope returns
  (`AnimationCompletionTests`).
- **Why:** a frame is one pass, and a pass runs under one transaction. A
  body's observation fires once, at the first write to anything it read, and
  Observation has no public way to see the writes after it: when the first
  was unanimated, the scope's transaction is taken for its change. Its
  completions are taken with it because that is right where the scope did
  write what the body read — the case this exists for, whose completion
  SwiftUI runs when the animation ends — and TUIkit cannot tell the two
  cases apart; run as the scope returned, they would come before the
  animation had begun.
- **Decided:** [B-APPSTATE-2](<Decisions/State and dynamic properties/Per-app render state (APPSTATE).md#b-appstate-2-an-observed-change-reported-with-no-transaction-takes-the-next-scopes>). **Lane.**

### A8. A matched view is laid out again at each frame's size, and a removed one is carried at the size it was

- **SwiftUI (measured, macOS 15.8, 2026-10-18,
  [`Tools/SwiftUIProbes/Matched geometry/mg3.out`](<../../Tools/SwiftUIProbes/Matched geometry/mg3.out>)):** a view inserted as another of its id is removed is
  laid out at each frame's interpolated size; a follower whose `id` changes
  is laid out once at its new size and its drawing scaled between the two
  frames; the removed view moves toward the inserted one's frame as it fades,
  laid out at its own size and placed in that frame.
- **TUIkit:** every carried view is laid out again at each frame's size,
  edges rounded to whole cells, and only moved while its size is its own;
  while it is carried it floats over every view, a layer of its own over the
  page — where `.offset` is drawn at its place in the stacking order (L6) —
  and only at rest is it drawn at its place in the stacking order —
  there a terminal's blank cells paint, so a view carried toward the views
  before it would be lost under every container after it;
  the removed view's own cells — found by its geometry marker in the picture
  it left — are carried with the inserted one at the size it was, placed in
  that one's frame as a content of its size is, while what was drawn round
  it in that picture fades where it was, as SwiftUI's does; a transition
  that fades the inserted view fades the cells it draws at another view's
  frame too, as it moves (both 2026-10-19, decisions B-O4-1, B-O4-2). A
  source that its parent moves is not animated by the effect, so a view under
  both an animated layout and a matched geometry effect moves once.
- **Why:** a cell cannot be scaled (refusal review O4, ruled 2026-10-12: a
  re-layout per frame, with translation where the sizes are equal); a
  removed view's content is the picture it last drew (A3), which cannot be
  laid out again.
- **Decided:** [O4](<Refusals re-examined, wave 17 (2026-10-03).md#o4-matched-geometry-matchedgeometryproperties--w12-matchedgeometryeffect-zoom-matchedtransitionsourceconfiguration-emptymatchedtransitionsourceconfiguration--w09-matchedtransitionsource-navigationtransitionzoom>),
  [B-O4-1, B-O4-2, B-O4-7](<Decisions/Shapes, effects and animation/Matched geometry and the zoom transition (O4).md>).
  **Owner** (the re-layout), **Lane** (the rest).

### A9. A zoom navigation transition is a reveal

- **SwiftUI (Apple's documentation; iOS-only, so not measured here):**
  `.zoom(sourceID:in:)` scales the pushed view up from its source's frame,
  clipped to the source's `clipShape`, and down into it when it is popped.
- **TUIkit:** the pushed screen is laid out at its full size and uncovered
  through a rectangle growing from the source's frame to the stack's, over
  the screen it replaces; a popped screen is covered back down into the
  source over the screen it returns to. A push with no animation of its own
  zooms under `Animation.default`; none zooms where the transaction disables
  animations, motion is reduced, or no source is on screen. The source's
  `clipShape(_:)` cuts the rectangle's corners by the ½ rule a clip keeps,
  and its `shadow(color:radius:x:y:)` falls on the screen it grows over, in
  cells; both go from the source's to nothing as the rectangle reaches the
  stack ([B-W1B-2](<Decisions/Shapes, effects and animation/What the shapes unblocked (W1B).md#b-w1b-2-a-zoom-sources-clip-shape-and-shadow-shrink-to-nothing-as-the-rectangle-grows>)).
  (`ZoomNavigationTransitionTests`.)
- **Why:** a cell cannot be scaled (refusal review O4, ruled 2026-10-12: the
  zoom is the `.scale` reveal generalised).
- **Decided:** [O4](<Refusals re-examined, wave 17 (2026-10-03).md#o4-matched-geometry-matchedgeometryproperties--w12-matchedgeometryeffect-zoom-matchedtransitionsourceconfiguration-emptymatchedtransitionsourceconfiguration--w09-matchedtransitionsource-navigationtransitionzoom>),
  [B-O4-5](<Decisions/Shapes, effects and animation/Matched geometry and the zoom transition (O4).md>). **Owner** (the reveal),
  **Lane** (the default animation).

### A10. A branch, a case and a row with no transition fade in, and go at once

- **SwiftUI (measured, macOS 15.8, 2026-10-19,
  [`Tools/SwiftUIProbes/Transitions/tr1.out`](<../../Tools/SwiftUIProbes/Transitions/tr1.out>) T1–T3, T8):** with
  no `.transition` written, a view an animated change puts in fades in where
  it lands, and one it takes out fades out where it was, drawn beneath its
  siblings while they glide: the branch an `if`/`else` flips to and the one
  it leaves, a `switch`'s case, a `ForEach`'s row and an `if`'s view alike.
- **TUIkit:** an `if`'s view fades in and out. The branch an `if`/`else`
  takes, a `switch`'s case and a `ForEach`'s row fade in where they land;
  the branch it leaves, the case left, a row removed and, in a stack, what
  an `if` hands the stack rather than holding itself — several views, a
  `Group`, an `if`/`else`, or a view under an `.id` written on the `if` — go
  on the frame of the change, while the views around them glide into the
  room. An `if` rendered directly fades out whatever it holds. A branch, a
  case or a row with a transition of its own plays it on the way out, where
  it was, unless something is drawn round the transition, when it goes at
  once. The branch a conditional drawn whole leaves goes the same way
  (`BranchAndRowFadeTests`, `ConditionalRecordTests`). Where nothing
  remembers the children — a lazy stack, a `Grid`, a `List`, a `Table` —
  they come at once as well (Slated).
- **Why:** fading a view out after it has gone needs what it drew on the
  frame before, the one thing left of it, so every container kept every
  child's picture from one frame to the next, settled or not. With nothing
  animating that cost up to +7.2% a frame (`tables-scroll`), +2–3.5% across
  a dozen scenarios, and `deep`'s footprint 17.1 → 32.6 MB (A/B,
  2026-10-19). Keeping only the pictures of children that can go still kept
  the rows and branches those scenarios are made of. The owner's rule for
  the default transition (2026-10-14) was to fade both ways and fall back to
  fading in only at a significant cost, above all with no animation. An
  `if`'s view keeps its fade-out: its `if` keeps one picture, which passed
  its own A/B on 2026-10-14.
- **Decided:** [B-TR2PERF-1](<Decisions/Shapes, effects and animation/Default fade cost (TR2PERF).md#b-tr2perf-1-a-branch-a-case-and-a-row-fade-in-and-go-at-once>),
  [B-TR2PERF-2](<Decisions/Shapes, effects and animation/Default fade cost (TR2PERF).md#b-tr2perf-2-an-ifs-view-keeps-its-fade-out>).
  **Owner** (the fallback, 2026-10-14); **Lane** (the measurement).

---

## Scrolling

### R1. Scrolling moves in whole lines, and only a `ScrollView`'s programmatic scrolls animate

- **SwiftUI:** scrolls in points, with momentum; an animated `scrollTo`
  animates; phases include `.tracking`, `.decelerating` and `.animating`, with
  a velocity; a bounce springs back (the `scrollTo` phases measured, B27; the
  rest Apple's documentation).
- **TUIkit:** an offset is whole rows and columns. A `ScrollView`'s `scrollTo`
  or `ScrollPosition` row request made inside `withAnimation` glides there a
  whole line at a time along the animation's curve (its first pass only, for
  a repeating one), drawn only on the 1/60 s ticks where its line changes
  (since 2026-10-24, B27-ANIMATING); under reduce motion it jumps. A
  `List`'s or a `Table`'s, a column request, and a position's edge or offset
  still jump. A user scroll is `.interacting` until 250 ms pass with no step; a
  glide is `.animating` until it lands; `.tracking` and `.decelerating` never
  occur; the velocity is (0, 0) at every report,
  as SwiftUI's is where it was measured. An overscroll
  allowance the app asked for stays where it was pushed (bounce behaviour
  decides only when it applies); `.always` adds a bounce of a line or two on an
  end with none, sprung back a line a frame once the scroll goes idle, and
  pushed by a scroll view's arrow or page key at the end as by the wheel (a
  focused `List`'s or `Table`'s keys move its cursor instead).
- **Why:** a terminal reports no gesture phases and no momentum, and draws
  no line between two of its rows. The lists' requests join the glide later
  ([the design note](<Decisions/Scrolling/Animated scrolling, a design (B27).md>), pieces 4–8).
- **Decided:** [B27](<Decisions/SwiftUI API completion decisions.md#b27-scroll-phases-interacting-until-a-quarter-of-a-second-of-quiet-and-no-velocity>), [B27-ANIMATING](<../Open owner decisions.md#b27-animating>), [B30](<Decisions/SwiftUI API completion decisions.md#b30-the-transaction-scroll-members-what-no-adjustment-suspends>), [B31](<Decisions/SwiftUI API completion decisions.md#b31-bounce-behaviour-gates-the-overscroll-allowance-and-always-springs-back>).
  **Medium**. The owner decided on 2026-10-12 that the velocity is (0, 0) at
  both changes, as SwiftUI reports it, and to add a bounce under `.always`;
  both shipped 2026-10-13.

### R2. A default scroll anchor quantises to three edges, and ignores x but to align

- **SwiftUI:** `.center` keeps the centre fixed; `x` places content on a
  horizontal view (measured, macOS 15, B-D2S-1).
- **TUIkit:** for where a view opens and what it holds, `y ≥ 0.75` is the
  bottom, `y ≤ 0.25` the top, and anything between anchors nothing, and `x`
  is ignored. The alignment role places narrow content by `x` on a view that
  scrolls across, as SwiftUI's does (since 2026-10-19), except content that
  fills whatever width it is offered, which is drawn at the viewport's width
  where SwiftUI places its ideal width. SwiftUI's two-axis alignment
  arithmetic, which draws an item past the view's bounds, is not copied: each
  axis is placed by its own coordinate.
- **Why:** an offset is whole rows, so there is no centre to hold between two
  of them, and the anchor modes are defined over rows.
- **Decided:** [UnitPoint.swift](../../Sources/TUIkitFoundation/Views/UnitPoint.swift#L224-L235),
  [B-D2S-1](<Decisions/Scrolling/Scroll anchors, target behaviours and clipping (D2S).md#b-d2s-1-the-alignment-role-places-content-on-the-vertical-axis-only>). **Recorded.**

### R3. `ScrollPosition.viewID` answers sooner

- **SwiftUI:** a `ScrollPosition`'s readings are the request until the user
  scrolls: after `scrollTo(y: 100)`, `point`, `viewID` and `edge` are `nil` and
  `isPositionedByUser` is `false`; after an animated `scrollTo(id: 10)`,
  `viewID` is `10`. `viewID` names a row the user scrolled to only once the
  user has scrolled (measured, macOS 15, Wave 10).
- **TUIkit:** the request and the reported row are held separately, and the
  request stays readable until the user scrolls, as SwiftUI's does. But
  `viewID(type:)` also answers on the first frame and after a programmatic
  scroll, with the row the view reports. A reading SwiftUI would give is never
  different, only present sooner. Only code that takes "`viewID` is `nil`" to
  mean "the user has not scrolled yet" behaves differently, and
  `isPositionedByUser` is the test for that.
- **Why:** reading the binding tells an app where the view ended up, however
  it got there; the read-back predates the request model, and its tests pin
  it.
- **Decided:** decisions B23, folded here and removed on 2026-10-12.
  **Owner** (2026-10-04: keep TUIkit's extras if they are source-compatible,
  which they are; 2026-10-12: keep).

### R4. `ScrollGeometry` leaves out the bars

- **SwiftUI:** overlay scrollers, so the visible area is the frame (every
  reading B26 lists was measured).
- **TUIkit:** `containerSize` is the viewport less the bar (and less the
  "N more" lines where they are reserved). A vertical view's
  `contentSize.width` is the width it lays its content out at.
- **Why:** a terminal's bar takes cells from the viewport, so what is visible
  is what is left. That keeps the reading apps rely on exact:
  `visibleRect.maxY` reaches `contentSize.height + contentInsets.bottom` at
  the bottom, and no further. The whole frame would make `visibleRect` a cell
  wider than what can be seen. For full-width rows, the common case, the
  content's own width and the layout width are the same number; measuring the
  content across every frame an observer is attached is cheap to add if a use
  turns up.
- **Decided:** decisions B26, folded here and removed on 2026-10-12.
  **Owner** (2026-10-12: keep).

### R5. A scroll indicator is part of the viewport, and always drawn

- **SwiftUI:** overlay scrollers, hidden until something scrolls, hence
  `scrollIndicatorsFlash` (Apple's documentation). SwiftUI's documentation
  says `.scrollContent` margins inset the content "without affecting the
  insets of its scroll indicators", and `.automatic` inset both. Measured on
  macOS 15.8 (2026-10-12, legacy scrollers as the terminal's analogue,
  `Tools/SwiftUIProbes/Scroll position, margins and disabled scrolling (DECB)/margins/`): `.scrollIndicators` margins place the
  scroller exactly as TUIkit places its bar, shortened by the top and bottom
  margins and moved in by the trailing one, with the columns it moves in by
  taken from the content; `.automatic` agrees by outcome; and `.scrollContent`
  gives exactly `.automatic`'s state, scroller moved too, which contradicts
  the documentation.
- **TUIkit:** the bar is a column or row of the viewport, drawn on every frame
  the content overflows. A vertical bar is shortened by the top and bottom
  margins and moved in by the trailing one, under `.automatic` and
  `.scrollIndicators` margins; `.scrollContent` margins leave it at the edge.
  `scrollIndicatorsFlash` highlights the indicators for half a second instead
  of revealing them.
- **Why:** a bar is a column of cells and cannot float over content.
  TUIkit's `.scrollContent` follows SwiftUI's documentation, not macOS's
  behaviour, which contradicts it: an app that wants the bar left at the edge
  says `.scrollContent`, and one that wants it moved says `.scrollIndicators`.
- **Decided:** decisions B24, folded here and removed on 2026-10-12 (the owner
  asked what was recommended; keeping this rule was, with the measurement
  above); [B28](<Decisions/SwiftUI API completion decisions.md#b28-scrollindicatorsflash-flashes-the-indicators-for-half-a-second>). **Medium**. The owner asked for a flash to be
  built (2026-10-12): a highlight, shipped 2026-10-13.

### R6. Rows are reported without `scrollTargetLayout()`

- **SwiftUI:** a scroll view reports through `.scrollPosition(id:)` only the
  views of a layout marked with `scrollTargetLayout()` (Apple's
  documentation).
- **TUIkit:** a vertical stack's rows, lazy or eager (the eager since
  2026-10-15), and a horizontal stack's columns in a horizontal-only scroll
  view (since 2026-10-15), are reported whether or not marked, to
  `.scrollPosition(id:)` and (since 2026-10-19) to
  `onScrollTargetVisibilityChange`; the mark matters only to `.viewAligned`,
  which aligns to the marked stack's rows. So
  SwiftUI code without the mark (forgotten, or a binding used only to scroll)
  behaves differently: a user's scroll writes the binding here, and can fire
  an `onChange` SwiftUI never fires. A scroll view that scrolls both ways
  reports its rows only.
- **Why:** reading back where the view is predates the mark, and most SwiftUI
  code that reads the binding marks a layout, because SwiftUI reports nothing
  otherwise, so it reads the same here (estimate).
- **Decided:** decisions B29, folded here and removed on 2026-10-12 (the owner
  asked whether the difference is intentional: it is, and documented at
  [ScrollTargetBehavior.swift](../../Sources/TUIkitFoundation/Views/ScrollTargetBehavior.swift#L357-L363)).
  **Lane.**

### R7. `List` and `Table` keep their own scrolling rules

- **SwiftUI (measured, macOS 15):** a `List` never consults a custom scroll
  target behaviour, and honours `scrollClipDisabled`.
- **TUIkit:** `List` and `Table` honour the built-in behaviours only;
  `.viewAligned` aligns rows at the top whatever its anchor; under
  `scrollClipDisabled` a `List` draws the row past each edge of its window
  outside its frame (drawn, not clicked), and a `Table` keeps clipping.
- **Why:** a list's offset is a row and a clip; a custom behaviour would need
  every row's height above the viewport, the walk a list exists not to make.
- **Decided:** [B-D2S-2](<Decisions/Scrolling/Scroll anchors, target behaviours and clipping (D2S).md#b-d2s-2-list-and-table-honour-the-built-in-behaviours-and-no-behaviour-of-the-apps-own>), [B-D2S-3](<Decisions/Scrolling/Scroll anchors, target behaviours and clipping (D2S).md#b-d2s-3-in-a-list-or-table-viewaligned-aligns-rows-at-the-top-whatever-its-anchor>),
  [B-D2S-4](<Decisions/Scrolling/Scroll anchors, target behaviours and clipping (D2S).md#b-d2s-4-scrollclipdisabled-reaches-scrollview-list-and-table-keep-clipping>). **Lane.**

### R8. An unclipped scroll view's overflow is hidden line by line

- **SwiftUI:** under `scrollClipDisabled` a later view hides the overflow where
  its glyphs are drawn (measured).
- **TUIkit:** on each line of the later view, from its first painted cell to
  its last; unstyled blank cells either side hide nothing, and a click on
  overflow drawn there is the overflow's.
- **Why:** a cell is drawn or not, so "where it draws" has to be said in
  cells.
- **Decided:** [B-D2S-5](<Decisions/Scrolling/Scroll anchors, target behaviours and clipping (D2S).md#b-d2s-5-a-later-view-hides-an-unclipped-scroll-views-overflow-from-its-first-painted-cell-to-its-last>). **Medium.**

### R9. A pinned header is opaque, and focus keeps rows clear of it

- **SwiftUI:** a pinned section header has no background; rows show through
  where it draws nothing (measured).
- **TUIkit:** the header's cells replace the rows' glyphs across the section's
  width (a cell's background shows through). It sits below an "N more above"
  line. Focus moving onto a row scrolls it clear of a pinned header; a
  programmatic `scrollTo(_:anchor: .top)` puts the row under it, as SwiftUI
  does.
- **Why:** a cell holds one glyph, so a row's text showing beside a short
  header reads as one garbled line.
- **Decided:** [B66](<Decisions/SwiftUI API completion decisions.md#b66-a-pinned-header-covers-the-rows-under-it-swiftuis-lets-them-show-through>), [B67](<Decisions/SwiftUI API completion decisions.md#b67-under-the-n-more-above-line-a-pinned-header-sits-below-it>), [B69](<Decisions/SwiftUI API completion decisions.md#b69-focus-keeps-a-row-clear-of-a-pinned-header-a-seek-does-not>).
  **Medium.**

### R10. Scroll visibility and coordinate spaces

- **SwiftUI:** a lazy row that scrolls away is destroyed and reports nothing
  (measured, B-D5G-1); `.scrollView` inside a `List` row is the list's own
  space (not measured).
- **TUIkit:** a row windowed out of a lazy stack is still in the tree and is
  reported hidden. `.scrollView` inside a `List` row is the list's content
  window, as in SwiftUI (since 2026-10-19), but its rows are not placed before
  they are drawn, so a scrolled list with a reader in its rows draws it twice a
  frame. A `ScrollViewReader` finds an `.id(_:)` only on
  the stack's own children; a `ForEach` row is found by its element's id.
- **Why:** the row is still there (F1), and an app that stops a player on
  "hidden" must hear it. A list renders its rows into a window under its
  chrome, and tells them its own origin until it knows where the window put
  them.
- **Decided:** [B-D5G-1](<Decisions/Layout and geometry/Coordinate spaces, geometry and scroll visibility (D5G).md#b-d5g-1-scroll-visibility-a-removed-view-is-not-reported-a-row-windowed-out-of-a-lazy-stack-is>), [B-D5G-9](<Decisions/Layout and geometry/Coordinate spaces, geometry and scroll visibility (D5G).md#b-d5g-9-a-lists-rows-are-not-placed-by-the-prediction-and-a-list-does-not-own-scrollview>),
  [ScrollViewReader.swift](../../Sources/TUIkitFoundation/Views/ScrollViewReader.swift#L47-L52).
  **Lane.**

### R11. `ScrollPosition.scrollTo(id:anchor:)` honours its own anchor

- **SwiftUI:** `ScrollPosition.scrollTo(id:anchor:)` ignored the call's anchor
  in the probe: `.top` and `.center` both landed at the minimal position, and a
  transaction's `scrollTargetAnchor` applied even over a `.bottom` call
  (measured, macOS 15.8, 2026-10-12, `Tools/SwiftUIProbes/Scroll position, margins and disabled scrolling (DECB)/anchor/`).
  `ScrollViewProxy.scrollTo` honours the call's anchor first, then the
  transaction's.
- **TUIkit:** both honour the call's anchor first, then the transaction's.
- **Why:** SwiftUI's `ScrollPosition` reading looks like a defect, and one
  rule for both seeks is easier to rely on.
- **Decided:** [B30](<Decisions/SwiftUI API completion decisions.md#b30-the-transaction-scroll-members-what-no-adjustment-suspends>), recorded as a deliberate deviation on
  2026-10-12. **Lane.**

### R12. "No adjustment" suspends an eager stack's follow too

- **SwiftUI:** `Transaction.scrollContentOffsetAdjustmentBehavior = .disabled`
  stops a lazy stack's bottom follow under `defaultScrollAnchor(.bottom)`, and
  its hold of the top row when rows are inserted above; with an eager `VStack`
  the follow happens anyway (measured, macOS 15.8, 2026-10-12,
  `Tools/SwiftUIProbes/Scroll position, margins and disabled scrolling (DECB)/disabled/`).
- **TUIkit:** `.disabled` suspends a declared anchor's adjustments for that
  change in a `ScrollView`, `List` or `Table`, whether the content is eager or
  lazy.
- **Why:** one rule for both kinds of stack; SwiftUI's split looks incidental.
- **Decided:** [B30](<Decisions/SwiftUI API completion decisions.md#b30-the-transaction-scroll-members-what-no-adjustment-suspends>), recorded as a deliberate deviation on
  2026-10-12. **Lane.**

### R13. `List` and `Table` hold the row at their top

- **SwiftUI (measured, macOS 15.8, 2026-10-12,
  `Tools/SwiftUIProbes/Scroll anchoring/hold.swift` cases 13–15):** a lazy stack
  in a scroll view keeps the row at its top in place when rows are inserted
  above it; a `List` does not — its origin stays, and the rows move down. iOS
  is not measured.
- **TUIkit:** `List` and `Table` keep their top row in place too, under the
  default `ScrollWindowHold.topRow` (`ItemListHandler.holdTopRow`,
  `ScrollWindowHoldTests`); `.scrollWindowHold(.offset)` gives macOS's
  behaviour.
- **Why:** the owner's ruling is to keep the reader's place when rows arrive
  above, and a list is where that matters most; one rule for every scrollable.
- **Decided:** [A-SCROLLANCHOR-1](<Decisions/Scrolling/Scroll anchoring default (SCROLLANCHOR).md#a-scrollanchor-1-list-and-table-hold-their-top-row-where-macoss-list-does-not>).
  **Owner** (2026-10-13: one rule for every scrollable, and the place, not the
  offset, is the better default).

### R14. Removing rows above the top row does not move the rows on screen

- **SwiftUI (measured, macOS 15.8, 2026-10-12,
  `Tools/SwiftUIProbes/Scroll anchoring/hold.swift` case 2,
  `reorder.swift`):** a lazy stack holds its top row through an insertion
  above it, not a removal: five rows removed above leave the origin where it
  was, and the rows on screen move up; nor a row moved from below the screen to
  above it, nor one moved from above to the end.
- **TUIkit:** the top row keeps its line whichever way the content above it
  changed — inserted, removed, moved past it, or a measured row above resized
  — as long as the row before it or the row after it moved alike; a reorder
  that parts it from both (a sort) keeps the offset, as SwiftUI's does
  (`ScrollWindowHoldTests`). A top row whose id changed in the change that
  inserted rows above it keeps its place, where SwiftUI holds nothing
  (`beside.out` case 2, B-SCROLLANCHOR-6).
- **Why:** the reader's place does not depend on which way the rows above
  changed, and one rule is simpler to rely on.
- **Decided:** [B-SCROLLANCHOR-1](<Decisions/Scrolling/Scroll anchoring default (SCROLLANCHOR).md#b-scrollanchor-1-a-removal-above-and-a-row-above-growing-are-held-as-an-insertion-is>).
  **Lane.**

### R15. Under a top or leading margin, `.paging` steps the container

- **SwiftUI (measured, macOS 15.8.1, 2026-10-19,
  `Tools/SwiftUIProbes/Scroll target behaviours/margins2.swift`,
  `hmargins.swift`):** the behaviour is handed the container less the
  content margins, as documented, but `.paging` steps the container plus half
  the top margin (vertically) or the leading margin (horizontally): 90 points
  through a 70-point window under a top margin of 40. With only a bottom or
  trailing margin it steps the container.
- **TUIkit:** `.paging` steps the container, the window less the margins, so
  every page lands inside them and a page sized with `containerRelativeFrame`
  is the step (`ScrollTargetBehaviorTests.containerPagesUnderMargins`).
- **Why:** SwiftUI's page matches nothing an app can size its pages to, and
  nothing in its documentation describes it; it looks like a slip, and
  copying it would make container-sized pages drift under margins.
- **Decided:** [B-SCROLL-1](<Decisions/Scrolling/Scrolling fixes and parity (SCROLL).md#b-scroll-1-paging-under-a-top-or-leading-margin-steps-the-container-not-swiftuis-half-margin-longer-page>).
  **Lane.**

---

## Lists, tables and controls

### V1. A plain click on the selected row clears a single selection

- **SwiftUI:** on macOS a plain click selects and never deselects;
  command-click clears (the `NSTableView` convention; Apple's prose does not
  state it, semantic audit item 1).
- **TUIkit:** with a `Binding<ID?>`, a click on the selected row clears it.
  With a `Binding<Set<ID>>` the macOS rule holds in full, with Ctrl-click and
  Option-click toggling a row in place of command-click (Ctrl-click opens the
  row's menu where it has one).
- **Why:** command-click does not reach many terminals, so the convention's way
  back to "nothing selected" is unavailable.
- **Decided:** [§2.11](<SwiftUI compatibility guide.md#211-a-plain-click-on-the-selected-row-clears-a-single-selection-where-macos-keeps-it>), [B-D4T-2](<Decisions/Lists and tables/Table and list actions, context menus and columns (D4T).md#b-d4t-2-ctrl-click-on-a-list-or-table-with-a-menu-opens-the-menu-not-a-toggle>). **Owner**
  (2026-09-21).

### V2. The keyboard cursor is apart from the selection

- **SwiftUI:** on macOS the keyboard cursor is the selection (measured,
  macOS 15.8, B-D4T-1).
- **TUIkit:** the arrows move a cursor and Space or Return selects. So
  `contextMenu(forSelectionType:menu:primaryAction:)`'s Return acts on the
  selection when the cursor row is in it and on the cursor row alone when not;
  type select moves the cursor; background prominence is raised for the cursor
  row (when it is selected) where SwiftUI raises every selected row; a sidebar
  tab view chooses a tab on Return, where a macOS sidebar selects as the cursor
  moves.
- **Why:** not recorded. Space toggling at the cursor is how the keyboard
  builds a selection ([§2.11](<SwiftUI compatibility guide.md#211-a-plain-click-on-the-selected-row-clears-a-single-selection-where-macos-keeps-it>)).
- **Decided:** [B-D4T-1](<Decisions/Lists and tables/Table and list actions, context menus and columns (D4T).md#b-d4t-1-returns-primary-action-acts-on-the-cursor-rows-set-not-on-the-selection-as-such>), [B73](<Decisions/SwiftUI API completion decisions.md#b73-background-prominence-raised-on-the-rows-a-list-builds-itself>), [B76](<Decisions/SwiftUI API completion decisions.md#b76-the-sidebar-style-a-list-beside-the-content-chosen-with-return>),
  [B77](<Decisions/SwiftUI API completion decisions.md#b77-type-select-moves-the-cursor-and-a-prefixs-first-character-gives-way-to-bare-key-bindings>). **Lane.**

### V3. List and table chrome differs from macOS by default

- **SwiftUI (measured, macOS 15.8):** `.automatic` lists and tables have no
  border; a list draws a separator under every row (not `.sidebar`); a
  `.standard` badge sits in a capsule; a section's actions show while the
  pointer is over it.
- **TUIkit:** `.automatic` is bordered; no separators unless asked; a
  `.standard` badge sits in a capsule in the control family (since
  2026-10-24: a field a cell wider each side under filled faces, line caps
  under `.controlStyle(.lines)`), as macOS's does, and is no longer a
  deviation; a section's actions show while the focused list's cursor or
  the focus is in the section as well as under the pointer (owner ruling
  B78-VISIBILITY, 2026-10-24; always shown before) — at the header's
  trailing edge in a list that fills its width, after the title in one that
  hugs its rows.
- **Why:** a separator costs a line per row; actions shown only on hover are
  out of the keyboard's reach, so the cursor and the focus show them too.
- **Decided:** decisions A29 and A46 (**Owner**, 2026-10-07: tables stripe by
  default, both keep their border; removed when they shipped),
  [A-D6L-1](<Decisions/Lists and tables/List and table stripes, surfaces, pinned headers and separators (D6L).md#a-d6l-1-the-surface-look-try-it-then-decide-what-if-anything-becomes-the-default>),
  [A-D6L-2](<Decisions/Lists and tables/List and table stripes, surfaces, pinned headers and separators (D6L).md#a-d6l-2-should-a-list-draw-separators-by-default>), [B72](<Decisions/SwiftUI API completion decisions.md#b72-badge-prominence-two-inks-read-from-the-lists-environment>),
  [B78](<Decisions/SwiftUI API completion decisions.md#b78-section-actions-shown-while-the-section-is-in-use-after-the-headers-title>). **Under review** (borders and separators),
  **Lane** (the rest).

### V4. A table row is one line unless asked

- **SwiftUI:** a row grows to its tallest cell, and a table's rows are lazy
  (measured, macOS 15.8, wave 8a's note in the decisions file).
- **TUIkit:** a cell is one line unless its column's `lineLimit(_:)` allows
  more; the TUI-only `.tableRowHeights(.automatic)` opts into growth. Rows are
  flattened when the table is built, so a `ForEach`'s content runs once per
  element per build. A section header is drawn as lines of the row below it.
- **Why:** the row height is the owner's answer to B44; the rest is not
  recorded.
- **Decided:** decisions B44 (the owner's answer, implemented by
  [lane D4T](<Decisions/Lists and tables/Table and list actions, context menus and columns (D4T).md#b-shipped-the-safe-option>)), [B-D4T-5](<Decisions/Lists and tables/Table and list actions, context menus and columns (D4T).md#b-d4t-5-a-section-header-is-lines-of-the-row-below-it-not-a-row-of-its-own>), [§1](<SwiftUI compatibility guide.md#1-match>) (the Data
  row). **Owner** (row height), **Lane** (the rest).

### V5. A collapsed `DisclosureGroup` keeps its content's state

- **SwiftUI:** collapsing takes the content out of the hierarchy, `@State`
  with it (not measured).
- **TUIkit:** the content's `@State`, `onChange` baselines and branches are
  kept while the group itself is on screen; `.task` and `onDisappear` are not
  covered.
- **Why:** a nested group opened, or a field typed in, should still be so when
  its parent reopens.
- **Decided:** [DisclosureGroup.swift](../../Sources/TUIkitFoundation/Views/DisclosureGroup.swift#L58-L63).
  **Recorded.**

### V6. Smaller differences in containers, controls and text

| Behaviour | SwiftUI | TUIkit | Decided |
|---|---|---|---|
| `listRowInsets` written twice on a row | the inner replaces the outer | the two add up | [ListRowStyleModifiers.swift](../../Sources/TUIkitLists/Modifiers/ListRowStyleModifiers.swift#L51-L54), **Recorded** |
| A row's `.top` separator | drawn where the style allows | declined; the line between rows is the upper row's `.bottom` | [B-D6L-2](<Decisions/Lists and tables/List and table stripes, surfaces, pinned headers and separators (D6L).md#b-d6l-2-a-rows-top-separator-is-the-styles-to-decline>), **Lane** |
| A row's `.badge(_:)` with a modifier after it other than an environment write (`.badge(5).padding()`) | the badge is drawn | no badge is drawn; write the badge outermost | [B-LISTS-1](<Decisions/Lists and tables/List, table and section fixes (LISTS).md#b-lists-1-a-rows-badge-is-read-through-environment-writes-only>), **Lane** |
| Return on a segmented picker | does nothing | chooses the segment under the cursor | [B-D2C-1](<Decisions/Presentation and windows/Pickers and sheet sizes (D2C).md#b-d2c-1-a-segmented-pickers-return-chooses-where-macoss-does-nothing>), **Lane** |
| `Stepper` and `Slider` | draw no value | draw a value read-out | [§1](<SwiftUI compatibility guide.md#1-match>) (Controls row), **Recorded** |
| `.automatic` and `.tabBarOnly` tab views | a segmented bar in the toolbar (measured) | a compact strip; `.grouped` draws folder tabs | [§1](<SwiftUI compatibility guide.md#1-match>) (Containers row), **Recorded** |
| A tab's label view | drawn as given | its text, in the strip's ink | [B75](<Decisions/SwiftUI API completion decisions.md#b75-a-tabs-label-is-drawn-as-text>), **Lane** |
| A table row a drop would land on | ringed in the accent | drawn as selected | [B80](<Decisions/SwiftUI API completion decisions.md#b80-table-row-drag-and-drop-the-rows-own-line-a-selected-look-flat-loops>), **Lane** |
| A drop at the end of a hierarchical table's branch | aimed at the branch's loop or the next row's by the pointer's indentation (measured) | the deeper loop that takes it | [B-LISTS2-7](<Decisions/Lists and tables/Lists, tabs and tables, settled parity items (LISTS2).md#b-lists2-7-a-slot-two-loops-of-a-hierarchical-table-reach-goes-to-the-deeper-loop>), **Lane** |
| Dragging a sidebar section | (a landing line between sections: not measured) | dropped onto another section's header, it takes that one's place | [B-LISTS2-4](<Decisions/Lists and tables/Lists, tabs and tables, settled parity items (LISTS2).md#b-lists2-4-a-sidebars-sections-move-among-the-identified-sections-and-a-drag-drops-onto-a-header>), **Lane** |
| `modifierKeyAlternate` in a menu | gets the modified view's shortcut plus its modifiers | takes no shortcut of its own | [B-D1K-2](<Decisions/Input, clipboard and text editing/Kitty keyboard protocol, key-press phases and UndoManager (D1K).md#b-d1k-2-a-modifier-key-alternate-in-a-menu-does-not-inherit-the-modified-views-shortcut>), **Lane** |
| A compact `DatePicker`'s calendar | (macOS keyboard unmeasured) | takes the keyboard as it opens | [B-D2C-2](<Decisions/Presentation and windows/Pickers and sheet sizes (D2C).md#b-d2c-2-a-compact-date-pickers-calendar-takes-the-keyboard-as-it-opens>), **Lane** |
| A `Section` that is a lazy stack row's `ZStack`'s only child | not the stack's own; does not pin | pins | [B68](<Decisions/SwiftUI API completion decisions.md#b68-which-sections-are-the-stacks-own-the-next-stack-down-and-one-sibling-step>), **Lane** |
| `.searchable`'s field | in the toolbar, presented by a click; scopes show while search is presented (documented) | always drawn at the top of the subtree; scopes show while it has the focus or a query | [B38](<Decisions/SwiftUI API completion decisions.md#b38-search-scopes-show-while-the-search-is-under-way-by-a-terminals-reading-of-presented-and-cancelled>), **Lane** |
| `.searchable` on a `TabView` (macOS 26) | the field goes into the `.search` tab (documented, unmeasured) | a field above the whole tab view | [A50](<Decisions/SwiftUI API completion decisions.md#a50-search-in-a-tab-view-macos-26-the-search-tab-and-its-activation>), **Owner** (2026-10-04: defer until macOS 26 can be measured) |
| `SystemFormatStyle.DateReference` between the measured readings | keeps a time zone of its own; turns at a new year's first instant (measured) | uses the calendar's zone; turns half a second early | [B49](<Decisions/SwiftUI API completion decisions.md#b49-systemformatstyle-where-the-rules-go-beyond-the-measurements>), **Lane** |
| An attributed format interpolated into a key | (a custom style's colours: not measured) | draws the characters only | [B88](<Decisions/SwiftUI API completion decisions.md#b88-an-attributed-format-interpolated-into-a-key-draws-the-characters-only>), **Recorded** |

---

## Presentation and window chrome

### W1. Toolbars are the window's two bars

- **SwiftUI:** on macOS, `.toolbar` items go to the window's toolbar;
  `.principal` is centred and `.status` centred in the toolbar (Apple's
  documentation).
- **TUIkit:** items join a top bar above the page and a bottom bar below it,
  each drawn only while something is placed in it. `.principal` replaces the
  title and `.status` goes to the bottom bar (iOS's readings). A bar appears or
  goes one frame after the page that changed it. The window's title is the
  outermost `.navigationTitle` drawn.
- **Why:** a bar's rows must be known before the page is laid out.
- **Decided:** [§2.6](<SwiftUI compatibility guide.md#26-toolbars-are-the-windows-bars-commands-are-its-menu-bar>). **Recorded.**

### W2. A toolbar in a popover draws round the view that declared it

- **SwiftUI:** a presentation's toolbar items go to its edges (not
  measured).
- **TUIkit:** a sheet and a full-screen cover host their toolbar items at
  their edges, as SwiftUI's do (lane TOOLBARS, B-D5C-3's fuller version). In
  a popover, `.toolbar` draws its modal actions in a button row below the view
  it is attached to, and its other placements in a row above it, so a
  `.toolbar` on an inner view of a popover puts its rows there. A popover
  presented from a sheet does the same: its items do not join the sheet's
  rows, and its `.toolbarVisibility(_:for:)` does not hide them.
- **Why:** the popover's presenter is in TUIkitFoundation, which cannot see
  the toolbar's module; the sheet's is in TUIkitPresentation, which can.
- **Decided:** [B-D5C-3](<Decisions/Menus, toolbars and chrome/Toolbars and opt-in window chrome (D5C).md#b-d5c-3-a-toolbar-in-a-sheet-draws-its-items-round-the-view-that-declared-it>). **Lane.**

### W3. Sheets are their content's size

- **SwiftUI (measured, macOS 15.8):** a sheet is never smaller than 100 × 80
  points; `.form` proposes 470 × 400; boxes in a `VStack` in a sized sheet are
  their content's size.
- **TUIkit:** no minimum; `.form` proposes `min(64, width)` columns by
  `min(25, height)` rows; boxes stacked in a sized sheet share its size.
- **Why:** a terminal sheet has no material, so its box is what shows its
  size.
- **Decided:** [B-D2C-3](<Decisions/Presentation and windows/Pickers and sheet sizes (D2C).md#b-d2c-3-form-is-25-rows-tall>), [B-D2C-4](<Decisions/Presentation and windows/Pickers and sheet sizes (D2C).md#b-d2c-4-no-minimum-sheet-size>),
  [B-D2C-5](<Decisions/Presentation and windows/Pickers and sheet sizes (D2C).md#b-d2c-5-a-sized-sheets-boxes-share-its-size-in-a-stack-and-size-to-content-in-a-scroll-view--nowhere-else>). **Lane.**

### W4. Detents and live sheets

- **SwiftUI (iOS):** the page keeps its height under a sheet that lets it
  through; a drag indicator shows on a sheet with one detent; a sheet presented
  from a sheet can leave the outer one live (Apple's documentation; not
  measured).
- **TUIkit:** the page is laid out in the rows above a live sheet, as a smaller
  terminal would lay it out. The grabber is a one-row rule, drawn only with two
  detents or more. A live sheet presented from a modal presentation is a modal.
- **Why:** Tab and the arrow keys would reach a page drawn under the sheet.
- **Decided:** [§4a](<SwiftUI compatibility guide.md#4a-swiftui-has-it--tuikit-should-add-it>) (the Presentation row),
  [B-D7S-1](<Decisions/Presentation and windows/Live and resizable sheets (D7S).md#b-d7s-1-the-grabber-is-a-rule-of-its-own-and-a-sheet-with-one-detent-has-none-whatever-the-indicator-says>), [B-D7S-4](<Decisions/Presentation and windows/Live and resizable sheets (D7S).md#b-d7s-4-a-live-sheet-presented-from-inside-a-modal-presentation-is-a-modal>). **Lane.**

### W5. A critical dialog's caution sign is an emoji

- **SwiftUI:** a large caution symbol beside the message (macOS's alert; not
  measured).
- **TUIkit:** the title starts with the warning-sign emoji (U+26A0 U+FE0F),
  keeping the warning colour on the border and title.
- **Why:** a terminal cannot draw the large picture; the owner asked for the
  sign.
- **Decided:** [B-D3M-1](<Decisions/Presentation and windows/Dialogs, image sizes, format styles and reduce motion (D3M).md#b-d3m-1-a-critical-dialogs-caution-sign-is-the-%EF%B8%8F-emoji-not-a-full-size-icon>). **Owner** (asked for it; the large
  picture is a later project).

### W6. Help shows in the status bar by default, and the keyboard can ask for it

- **SwiftUI:** `help(_:)` gives the view a help tag, which macOS shows as a
  tooltip beside the pointer once it rests on the view (Apple's
  documentation; the delay, and whether the keyboard can show one, not
  measured).
- **TUIkit:** the same text shows once the pointer rests on the view
  (`tooltipDelay`, 0.6 s), on any view, as a row of the status bar by default
  or as a panel beside the view under `tooltipStyle(.popover)`; the focused
  control's also shows on the help key `?`, and under `.tooltips(.onFocus)`
  when a control has the focus. `HelpRunLoopTests` pins hover, `?` and
  `.onFocus` through the run loop.
- **Why:** a terminal has no tooltip surface of its own: a row of chrome
  never covers the page, a panel does, and the choice is the app's. A key is
  the keyboard's way of pointing at the focused control.
- **Decided:** the owner's specification in
  [Tooltips and help in a terminal](<../Controls and presentation/Tooltips and help in a terminal.md>)
  (2026-08-24; both presentations, the app's choice, confirmed when they
  shipped, 2026-09-09), and the owner's 2026-10-12 ruling that views that
  cannot take the focus have help too. **Owner**.

### W7. The page's own shortcut on a command's key is asked first

- **SwiftUI:** on macOS a key equivalent goes to the key window's views first
  and to the main menu only if none takes it (AppKit's Cocoa Event Handling
  Guide, "The Path of Key Events"). Not measured in SwiftUI: the lane's probe
  (`Tools/SwiftUIProbes/The menu bar (O13)/menus.swift`) could not make its window key on
  this machine, and with no key window the main menu took the key.
- **TUIkit:** a `.keyboardShortcut` the window's content registers keeps its
  key when a command declares the same one; the command's fires where nothing
  on the page binds the key (`KeyboardShortcutRegistry.registeringCommands(_:)`,
  `MenuBarTests.pageShortcutWins`). The bar's own F10 follows the same rule: a
  page's handler that takes F10 is asked first (`MenuBarOpeningTests.pageF10Wins`).
- **Why:** the documented order. The menu bar renders after the page so that a
  command reads this frame's `@FocusedValue`, and "the last registration wins"
  would otherwise have handed every shared key to the menu bar.
- **Decided:** [B-O13-2](<Decisions/Menus, toolbars and chrome/The menu bar (O13).md#b-o13-2-the-pages-own-shortcut-on-a-commands-key-is-asked-first>). **Lane.**

### W8. No command works from behind a modal

- **SwiftUI:** on macOS the menu bar stays usable while a sheet is up; a
  command that reads a focused value sees the sheet's (not measured).
- **TUIkit:** while a modal holds the input the menu bar is drawn inert, as the
  top bar is: no menu opens — by key or by a click on a title — a menu open
  when the modal comes up closes, and no command's key fires from behind the
  modal (`MenuBarTests.inertUnderAModal`, `MenuBarOpeningTests.clickUnderAModal`).
  The modal's own keys work.
- **Why:** a terminal app has one window, and a command acting on the page
  hidden behind a sheet is a surprise the person cannot see; it is the rule
  every other channel of the page follows under a modal.
- **Decided:** [B-O13-3](<Decisions/Menus, toolbars and chrome/The menu bar (O13).md#b-o13-3-no-command-works-from-behind-a-modal>). **Lane.**

### W9. Windows open one at a time, each over the whole terminal

- **SwiftUI:** `openWindow` opens a window beside the others on the desktop,
  each where the window server places it; any of them can be clicked and
  typed into (Apple's documentation; not measured: no window can be opened on
  this machine, `O9/probe/scenes.swift`).
- **TUIkit:** the window opens over the whole terminal, in front of the one
  open; the window in front is the only one drawn and the only one the keys,
  the pointer and the focus reach. The windows behind are drawn off-screen, so
  their state, lifecycle and tasks carry on, and each comes back — its focus,
  its bars — when the one in front of it closes (`WindowPresentationTests`).
- **Why:** a terminal app has one surface. Refusal review O9, ruled
  2026-10-12: secondary scenes are full-surface covers stacked over the main
  one, room left for a real windowing model (the presenter's policy, which a
  tiling or overlapping one can replace).
- **Decided:** [B-O9-1](<Decisions/Presentation and windows/Several scenes on one surface (O9).md#b-o9-1-windows-are-full-surface-covers-stacked-over-one-another>). **Owner** (the policy), **Lane** (the details).

### W10. Escape closes a window opened over another

- **SwiftUI:** a window closes by its close button or ⌘W (macOS); Escape is
  the content's.
- **TUIkit:** with another window open behind it, Escape closes the window in
  front when nothing in it takes the key, as a pushed navigation screen's
  Escape goes back; the status bar calls it "close window"
  (`WindowPresentationTests.escapeClosesAndStateSurvives`). The window opened
  at launch, alone, keeps Escape for its content, as before, and so does a
  window whose content says `.windowDismissBehavior(.disabled)`, as macOS
  takes such a window's close button and ⌘W away (B-O9-10).
- **Why:** a terminal has no close button and no ⌘ key, and a window's content
  need not offer a way out; without one, a window opened over the main one
  would hold the reader.
- **Decided:** [B-O9-2](<Decisions/Presentation and windows/Several scenes on one surface (O9).md#b-o9-2-escape-closes-a-window-opened-over-another>). **Lane.**

### W11. Closing the last window quits the app

- **SwiftUI:** on macOS an app whose windows are all closed keeps running, with
  its menu bar, unless its only scene is a `Window` (Apple's documentation).
- **TUIkit:** the app quits when its last window closes — by `dismissWindow`,
  by `dismiss()` at a window's root, or by Escape — as `dismiss()` at the top
  quit it before (`WindowPresentationTests.lastWindowQuits`). An app that
  declares no window scene quits at launch.
- **Why:** a terminal app with no window open would show nothing, and could be
  given no input that opens one.
- **Decided:** [B-O9-3](<Decisions/Presentation and windows/Several scenes on one surface (O9).md#b-o9-3-the-last-window-closing-quits-the-app>). **Lane.**

### W12. Settings is a sheet over the window in front

- **SwiftUI:** on macOS the `Settings` scene is a window of its own, which
  `openSettings` opens or brings to the front (Apple's documentation).
- **TUIkit:** `openSettings`, `SettingsLink` and the menu bar's Settings…
  present the scene as a sheet over the window in front, its content's size;
  Escape or `dismiss()` closes it, and the window behind is inert while it is
  up (`SettingsSceneTests`).
- **Why:** refusal review O9, ruled 2026-10-12: `openSettings` presents the
  `Settings` scene as a sheet.
- **Decided:** [B-O9-6](<Decisions/Presentation and windows/Several scenes on one surface (O9).md#b-o9-6-settings-is-a-sheet-over-the-window-in-front>). **Owner.**

### W13. The Window menu closes a window; File has no New Window or Close

- **SwiftUI:** with several window groups, File ▸ New is a submenu with a New
  *Title* Window per group, and File holds Close (⌘W) and Close All (⌥⌘W); the
  Window menu holds Minimize, Zoom, the `Window` scenes and Bring All to Front
  (measured on macOS 15.8, `O9/probe/scenes.swift`).
- **TUIkit:** for an app that can have more than one window open — more than
  one window scene, or a window group that `openWindow` or its key opens more
  windows of — the Window menu holds Close Window, the open windows (the one in
  front checked) and the `Window` scenes; File gains nothing
  (`SceneMenuBarTests`). An app whose one window is all it can have has no
  Window menu.
- **Why:** a terminal has no minimising, zooming or bringing to front of other
  apps' windows, and ⌘W and ⌥⌘W reach a terminal app only as `commandKey`
  chords a text field may use; Close sits beside the list of windows it acts
  on, and Escape, which closes a window opened over another, is its key.
- **Decided:** [B-O9-9](<Decisions/Presentation and windows/Several scenes on one surface (O9).md#b-o9-9-the-window-menu-lists-the-windows-and-closes-the-one-in-front>). **Lane.**

### W14. A file panel is TUIkit's own, browsing the machine the app runs on

- **SwiftUI:** `fileImporter` presents the system's open panel (Apple's
  documentation), which browses the Mac's file system, opens on the folder the
  app last used, sorts folders and files together, and selects as the cursor
  moves (macOS's panels, not measured through SwiftUI).
- **TUIkit:** a panel TUIkit draws in a sheet (`FilePanel`): the folder's items
  in a `Table`, folders first, opening on the process's working directory and
  then on the folder of the last choice made through the modifier. Return opens
  a folder or chooses the item under the cursor (or the selection, when the
  cursor is in it), Space selects, Backspace goes up. It browses the
  file system of the machine the app runs on: over `ssh`, the remote one.
  `FileImporterPanelTests` pins the keys and the callbacks' order.
- **Why:** a terminal has no system panel to present; the ruling is a panel
  drawn for the terminal. Folders first is the terminal file managers' order,
  the working directory is where a terminal app's user is working, and the
  cursor is apart from the selection in every TUIkit list (V2). A remote
  session's app reads the remote disk, so that is the one to browse.
- **Decided:** refusal review [O10](<Refusals re-examined, wave 17 (2026-10-03).md#o10-file-panels-from-p16--ml>),
  ruled 2026-10-12; the details are [B-O10-1 to B-O10-4](<Decisions/Presentation and windows/File panels (O10).md>).
  **Owner** (the panel), **Lane** (the details).

### W15. A dialog's default button answers the Return its focused button lets through

- **SwiftUI:** an alert or confirmation dialog keeps `.disabled` and
  `.keyboardShortcut` written on its buttons and shows none of `.help`, `.tint`
  and `.foregroundStyle`; the button marked `.keyboardShortcut(.defaultAction)`
  is the default button, which Return chooses wherever the keyboard focus is
  (measured on macOS 15.8, the `NSAlert` read back:
  `Tools/SwiftUIProbes/Menu items and alert buttons/alert.out`).
- **TUIkit:** keeps the same two and drops the same three (`AlertAction`,
  `AlertButtonModifierTests`), but the default button answers Return only when
  the focused control lets the key through — TUIkit's rule for every default
  button, under which a focused button keeps its own Return
  (``KeyboardShortcut``). A dialog opens with the focus on its first button, so
  Return chooses that one until the focus moves.
- **Why:** the dialog's buttons are ordinary `Button`s in its focus section, and
  the default button's rule is the framework's, not the dialog's; opening on the
  default button is the fuller version, priced in the decision.
- **Decided:** [B-MENUS-1](<Decisions/Menus, toolbars and chrome/Menu parity (MENUS).md#b-menus-1-an-alert-keeps-disabled-and-keyboardshortcut-on-its-buttons-its-default-button-answers-the-return-the-focused-button-lets-through>).
  **Lane**.

### W16. Escape closes one submenu, and the pointer's way into a submenu is across

- **SwiftUI:** a `Menu` or a `Picker` in a menu is a submenu (measured on macOS
  15.8, `Tools/SwiftUIProbes/Menu items and alert buttons/pickers.out`); a
  radio-group picker there is its label and an empty row as disabled items,
  then its options as enabled items with none checked (measured, same file). Escape, with a submenu open, is believed to close the whole menu,
  and the pointer may cross other rows on its way into a submenu without closing
  it (macOS's tracking; neither measured).
- **TUIkit:** Escape closes the submenu the keys are in and goes back to its
  row; a second Escape closes the menu (`MenuSubmenuTests`). The pointer over
  another row closes the open submenu at once, so the way to a submenu's lower
  items is across, then down. A radio-group picker in a menu draws inline, its
  label over its options with the selected one checked (`PickerInMenuTests`).
- **Why:** Escape backing out one level is what the lane's brief asked for, and
  what Windows and GTK menus do: the keyboard's way out of a submenu that is
  not its way out of the menu. The pointer's grace needs the direction of its
  last moves, priced in the decision. macOS's radio-group form cannot be used:
  it shows no selection, so TUIkit checks the selected option, as a picker's
  other menu forms do.
- **Decided:** [B-MENUS-2](<Decisions/Menus, toolbars and chrome/Menu parity (MENUS).md#b-menus-2-a-menu-and-a-picker-in-a-pop-up-menu-are-submenus-opened-by-right-and-closed-by-left-or-escape>).
  **Lane**.
---

## Lifecycle

### F1. A row windowed out of a lazy container keeps its state

- **SwiftUI:** a lazy stack destroys a row a few updates after it scrolls away;
  its `@State` goes with it (Apple's `LazyVStack` documentation and WWDC26, as
  in L7).
- **TUIkit:** the row stays in the tree, with its state, while it is among the
  stack's rows. `onAppear` and `task` still fire on visibility, and
  `onScrollVisibilityChange` reports it hidden (R10).
- **Why:** L7's: TUIkit keeps no view objects, so nothing ends a row's state
  while the stack still lists the row.
- **Decided:** [§2.8](<SwiftUI compatibility guide.md#28-lazy-stacks-window-the-render-list-is-the-scalable-container>), [B-D5G-1](<Decisions/Layout and geometry/Coordinate spaces, geometry and scroll visibility (D5G).md#b-d5g-1-scroll-visibility-a-removed-view-is-not-reported-a-row-windowed-out-of-a-lazy-stack-is>). **Recorded.**

### F2. Animations carry on in an inactive scene

- **SwiftUI:** Apple advises pausing timers in an inactive scene (Apple's
  documentation).
- **TUIkit:** an unfocused terminal window is still on screen, so spinners and
  progress bars go on; only the focus indication holds still.
- **Why:** an unfocused terminal window is still on screen and still read.
- **Decided:** [FocusSystem](../../Sources/TUIkit/TUIkit.docc/Articles/FocusSystem.md#L345-L347).
  **Recorded.**

---

## Slated to change

Known differences that are not meant to stay, and open ones nobody has ruled
on. Each waits on the work, or on the ruling, its State names.

| Difference | Where | State |
|---|---|---|
| Size classes, `\.displayScale`, `\.dynamicTypeSize` and `\.isLuminanceReduced` are settable; the size classes are read by `.viewAligned`, and a written `.compact` makes a popover a sheet (a tab's too, since 2026-10-24), collapses a `NavigationSplitView` (A21), shows a `Table`'s first column alone and a `.sidebarAdaptable` tab view's strip (a `.bordered` or `.grouped` one's too, under `tabBarMinimizeBehavior`'s `.automatic`, since 2026-10-24), while nothing reads the other three. On macOS SwiftUI's own text ignores the last three too (measured), so this is a planned extension past macOS, not a difference from it | [B3](<Decisions/SwiftUI API completion decisions.md#b3-size-classes-are-settable-and-nothing-tuikit-draws-reads-them>) | Owner 2026-10-12: follow a written `.compact` where possible (popover to sheet, split-view collapse, compact `Table` and sidebar tab view); keep the defaults. All four shipped 2026-10-13 |
| `KeyboardShortcut.Localization` does not mirror under right-to-left | [B8](<Decisions/SwiftUI API completion decisions.md#b8-keyboardshortcutlocalization-is-recorded-and-every-strategy-behaves-as-custom>) | Owner 2026-10-12: mirror once right-to-left lands |
| A column places its children of one priority in order, cutting the trailing ones, where SwiftUI's shares its height as it shares a row's width (rows have since L14, 2026-10-13) | [`distributeInOrder`](../../Sources/TUIkitFoundation/Rendering/LinearSpaceDistribution.swift) | Owner 2026-10-13: follow SwiftUI. Landed and reverted for its cost (2400f2948): every overfull column asks each child its minimum, down the whole tree, every frame — counted, and the options priced, in [decisions A-LAYOUT-1](<Decisions/Layout and geometry/Layout parity (LAYOUT).md#a-layout-1-a-column-shares-an-overfull-height-only-once-a-childs-minimum-is-cheap-to-ask>). Waits on that, and on a fix: shared, a column squeezes a control of several lines in the middle |
| In a lazy stack, a `Grid`, a `List` and a `Table`, a view that an `if`/`else`'s branch, a `switch` or a `ForEach` row puts in under an animation appears at once, where SwiftUI's fades in (`.opacity`), and one with a `.transition(_:)` goes at once, where SwiftUI's plays it on the way out. An `if`'s view fades in and out everywhere (2026-10-14); a branch, a case and a row fade in, and play their own removal, in an eager stack, a `ZStack`, a `Layout` and a conditional drawn whole (2026-10-19), and go at once with none (A10) | [ChildFade.swift](../../Sources/TUIkitView/Animation/ChildFade.swift), [B-TRANSITIONS2-1](<Decisions/Shapes, effects and animation/Transition follow-ups (TRANSITIONS2).md#b-transitions2-1-a-branch-a-case-and-a-row-fade-in-where-a-container-remembers-its-children>) | Lane: the containers that window their rows or lay out a lattice keep no memory of their children yet (B-FB16-2, B-FB16-3, B-FB16-5); the fuller version is priced with theirs |
| A `TableColumn`'s header and a `Tab`'s title draw their key's Markdown words but not its styles (a field's title is plain words, as SwiftUI's placeholder is); every other control's title key is drawn styled (2026-10-15, 2026-10-18) | [B87](<Decisions/SwiftUI API completion decisions.md#b87-markdown-in-a-controls-title-key-parsed-though-a-column-header-and-a-tab-title-draw-only-its-words>), [B-PARITYMISC-3](<Decisions/Small parity items (PARITYMISC).md#b-paritymisc-3-a-column-header-and-a-tab-title-draw-their-keys-markdown-words-not-its-styles>) | Lane: the fuller version draws the styles |
| A modifier reaches multi-view content through some wrappers only | [§3](<SwiftUI compatibility guide.md#3-open-divergence>) | Open divergence |
| A child with no extent (an empty `VStack`, `Color.clear.frame(height: 0)`) takes no stack spacing; SwiftUI's takes it on both sides (measured 2026-09-24) | [§3](<SwiftUI compatibility guide.md#a-child-with-no-extent-takes-no-stack-spacing>) | Open divergence; the Example's Animation page relies on it |
| An `indirect` enum case's `update()` changes are not written back; nor any enum payload's on WebAssembly and Windows | [B-DYNVFIX-2](<Decisions/State and dynamic properties/Finding dynamic properties from declared types (DYNVFIX).md#b-dynvfix-2-an-indirect-enum-cases-payload-and-every-payload-on-webassembly-and-windows-is-updated-on-a-copy>) | Known; fuller version priced |
| A class property (S6): a closure made in a view other than the first drawn holding the object reads the first one's environment (a sheet's Done calling its page's `dismiss`); the `@State` in an enum case in a long-lived object follows the case's payload | [B-DYNVFIX-3](<Decisions/State and dynamic properties/Finding dynamic properties from declared types (DYNVFIX).md#b-dynvfix-3-what-a-class-property-holds-is-the-objects-every-view-drawn-holding-it-is-redrawn-by-its-writes-each-reads-its-own-environment-while-it-draws-and-an-object-made-with-a-view-value-keeps-its-views-state>) | Known; the fuller version priced |
