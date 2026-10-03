# Completing the SwiftUI API: Wave 10 (scrolling) decisions

*The Wave 10 companion to
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md),
in the same three parts and read the same way: once, at the end of the
straightforward work. A fourth, short part lists what this wave left to other
waves and lanes. Entries are numbered A-W10-1, B-W10-1 and C-W10-1 onwards
so they can sit beside the main document's without colliding.*

- **A. Needs your decision.** Nothing has shipped. Each entry gives the
  options, what each costs, and my recommendation.
- **B. Shipped the safe option.** A basic, honest form is in. Each entry says
  what the fuller version or the alternative reading would be, and what it
  would cost.
- **C. Declined without asking.** Recorded in `parity-map.json` as not
  implementable, because the reason seemed unarguable. Listed so they can be
  vetoed.

SwiftUI behaviour quoted as *measured* was measured on macOS 15 with an
offscreen `NSHostingView` (the probes are in the session notes, `w10/probe`).

---

## A. Needs your decision

### A-W10-1. Scroll target behaviours: SwiftUI's protocol, or keep `ScrollGranularity`?

*`View.scrollTargetBehavior(_:)`, `AnyScrollTargetBehavior` (+ `base`, `init(_:)`,
`properties(context:)`, `updateTarget(_:context:)`), `PagingScrollTargetBehavior`
(+ `init()`, `properties(context:)`, `updateTarget(_:context:)`), `ScrollTarget`
(+ `rect`, `anchor`), `ScrollTargetBehaviorContext` (+ `axes`, `containerSize`,
`contentSize`, `originalTarget`, `velocity`, `subscript(dynamicMember:)`),
`ScrollTargetBehaviorProperties` (+ `init()`), `ScrollTargetBehaviorPropertiesContext`
(+ `axes`, `environment`); and the two `renamed` map entries that point
`ScrollTargetBehavior` and `ViewAlignedScrollTargetBehavior` at `ScrollGranularity`*

SwiftUI calls a behaviour's `updateTarget(_:context:)` when a scroll gesture
ends, with the rect it would come to rest on, and lets the behaviour move it:
`.paging` rounds to a page, `.viewAligned` to the edge of a child of the
`scrollTargetLayout()`. TUIkit's answer today is `ScrollGranularity` — a
closed `.line`/`.row` choice for `List` and `Table` — and the map calls that a
rename, so `.scrollTargetBehavior(.paging)` does not compile.

A terminal's gestures end at every step: a wheel tick, a key, a scrollbar
release. So the protocol maps cleanly — each step proposes its destination as
a `ScrollTarget`, the behaviour adjusts it, the view lands there — with
`velocity` the step's direction and rate (a `CellVector`, B-W10-5), and
`.paging` turning every step into a page. `.viewAligned` needs the children's
edges: `List` and `Table` have them (that is `ScrollGranularity.row`), a
windowed `LazyVStack` knows its rows' offsets, an eager stack does not say.

**Options.**

1. **SwiftUI's model, staged.** The protocol and its types, custom behaviours,
   and `.paging` on `ScrollView`, `List` and `Table` — about a day.
   `.viewAligned` on `List`/`Table` over `ScrollGranularity.row` — half a day;
   on a `ScrollView`'s windowed stack — a day, once the lane changing the
   stack files has landed (the row edges come through the scroll window's
   reply). `ScrollGranularity` stays as the TUI-specific `.line` knob.
2. **Keep the rename.** Nothing to do; ported carousels and pagers do not
   compile.

**Recommendation:** 1. Paging and view-aligned scrolling are common in ported
code, and the gesture model fits a terminal better than it first looks.

### A-W10-2. Scroll visibility needs a way to find a view inside the scroll content

*`View.onScrollVisibilityChange(threshold:_:)`,
`View.onScrollTargetVisibilityChange(idType:threshold:_:)`*

Measured in SwiftUI: every observed view reports once when it first appears —
`true` or `false` — then at each crossing of the threshold (0.5 by default)
of its fraction inside the scroll view's viewport; a view in no scroll view
reports its visibility in the window; `onScrollTargetVisibilityChange` reports
the ordered ids of the `scrollTargetLayout()` children past the threshold.

A view does not know where it is until its ancestors composite it (the A2
problem), so the scroll view has to find the observed views in its content
after drawing it. That is A2's question in another form.

**Options.**

1. **Build on A2's G1 markers**, if you choose them: the observed view stamps a
   marker, the nearest scroll view measures each marker against its viewport
   (the root against the screen), fires on crossings, and fires `false` for a
   marker that has vanished — a row windowed out of a lazy stack's band, which
   has certainly left the viewport. About a day after G1.
2. **Standalone**, if A2 goes another way: the same, with the marker carried as
   a hit-test region from a reserved handler-id range that the mouse
   dispatcher skips (regions already travel through every combinator and are
   how the focus reveal finds a control). One more test per region in hit
   testing, and the same day of work.
3. **Approximate with appearance** (visible ⇔ drawn in a band): wrong for
   eager content and for thresholds. I don't recommend it.

`onScrollTargetVisibilityChange` also needs the target layout's children and
their ids, which the stack files carry — the other lane's — so it lands after
them either way. `scrollTransition` (deferred below) needs the same
measurement.

**Recommendation:** decide A2 first; then 1, or 2 if A2 does not choose markers.

### A-W10-3. `ScrollAnchorRole.alignment`, and what the unlabelled anchor already means

*`ScrollAnchorRole.alignment`*

Measured in SwiftUI: a `ScrollView` whose content is shorter than its viewport
places it by the alignment anchor — and the **unlabelled**
`.defaultScrollAnchor(.bottom)` sets that role too, so three short rows sit at
the bottom of the viewport (`for: .initialOffset` alone leaves them at the top).
`List` ignores the role on macOS, unlabelled or not.

TUIkit's unlabelled `.defaultScrollAnchor(.bottom)` keeps short content at the
top, so a log or a chat with two lines in it draws differently from SwiftUI's
today, and `.alignment` is absent (the compatibility doc calls it deferred, not
refused).

**Options.**

1. **Parity:** the role on `ScrollView` (the content drawn at its own height,
   placed in the viewport by the anchor's `y`, its hit regions moved with it),
   and the unlabelled modifier setting it, as SwiftUI's does. `List` and
   `Table` ignore it, as macOS's do. Half a day and a Stress selfcheck; it
   changes the drawing of every app with a short bottom-anchored scroll view.
2. **The role only:** `for: .alignment` works; the unlabelled modifier stays as
   it is, a documented difference. Same cost, no existing drawing changes.
3. **Leave it absent.**

**Recommendation:** 1. A chat or log that starts at the bottom is what
`.defaultScrollAnchor(.bottom)` is written for.

### A-W10-4. `scrollContentBackground(_:)`: `.visible` has to paint something

*`View.scrollContentBackground(_:)`*

On macOS `List` and `Form` draw a background of their own, which `.hidden`
removes, and a `ScrollView` draws none until `.visible` asks for one. TUIkit's
scrollables draw no background of their own (a `List` paints row highlights,
nothing behind them), so `.hidden` and `.automatic` are already true here, and
SwiftUI's commonest use — `.scrollContentBackground(.hidden).background(…)` —
would draw as it does there. `.visible` is the case with something to do, and
the `Visibility` type is shared, so it cannot be left out on its own.

**Options.**

1. **Ship it:** `.visible` paints the palette's background behind a
   `ScrollView`, `List`, `Table`, `Form` or `TextEditor` — the page's own
   colour, which over a coloured container is what makes the scrollable
   "opaque". About three hours across the five controls.
2. **Leave it absent.** The `.hidden` idiom does not compile.

**Recommendation:** 1.

### A-W10-5. `scrollClipDisabled(_:)`: how much may draw outside the viewport?

*`View.scrollClipDisabled(_:)`*

SwiftUI stops clipping, and the content past the scroll view's bounds draws
over whatever is beside it. Its documented uses are shadows and scaled items
in a carousel. TUIkit clips a layer that is part of the content (an
`.offset`, an overlay) to the viewport, and draws only the viewport's lines.

**Options.**

1. **Layers only:** stop clipping the content's floating layers. About an
   hour, and partial: the content's own lines past the viewport still do not
   draw.
2. **Everything:** also draw the rendered content past the viewport as a
   floating layer around it, over the neighbours, with its hit regions. About
   a day; a lazy stack's band is what is drawn, as SwiftUI draws its nearby
   rows.
3. **Leave it absent until the pixel effects (Wave 16) decide shadows and
   scaling**, the reasons the modifier exists.

**Recommendation:** 3, then 2 if Wave 16 brings effects that reach past a
view's frame.

### A-W10-6. `scrollDismissesKeyboard(_:)` joins O8

*`View.scrollDismissesKeyboard(_:)`, `ScrollDismissesKeyboardMode` (+ `.automatic`,
`.immediately`, `.interactively`, `.never`),
`EnvironmentValues.scrollDismissesKeyboardMode`*

It is about the software keyboard, which macOS does not have either, so on
macOS every mode is inert — exactly refusal-review O8's question. Under O8's
recommended (b) it ships as a recorded, documented-inert value, as macOS's is;
under (a) it is declined with `submitLabel`. Nothing to decide here apart from
O8.

### A-W10-7. The scroll edge effects join O7

*`View.scrollEdgeEffectHidden(_:for:)`, `View.scrollEdgeEffectStyle(_:for:)`*

They style content passing under a bar, and nothing passes under a bar here
(B6). Refusal-review O7 already asks whether to ship them with the safe-area
design; these two modifiers are that question's modifiers.

## B. Shipped the safe option

### B-W10-1. `ScrollPosition`: the request and the row are read separately, and `viewID` answers sooner than SwiftUI's

*`ScrollPosition.init(idType:edge:)`, `.init(idType:point:)`, `.init(idType:x:)`,
`.init(idType:x:y:)`, `.init(idType:y:)`, `.point`, `.x`, `.y`, `.viewID`,
`.scrollTo(point:)`, `.scrollTo(x:)`, `.scrollTo(x:y:)`; and the behaviour of
`.isPositionedByUser` and `.viewID(type:)`*

Measured in SwiftUI:

- after `scrollTo(y: 100)`, `point`, `viewID` and `edge` are all `nil` and
  `isPositionedByUser` is `false` (so `y` holds the request — `y` itself is
  macOS 26 only and could not be read here);
- after an animated `scrollTo(id: 10)`, `viewID` is `10` and
  `isPositionedByUser` is still `false`.

So SwiftUI's readings are the *request*, until the user scrolls. TUIkit's were
the *report*: every frame the windowed stack named the row at the anchor,
overwrote the request with it, and set `isPositionedByUser` — on the first
frame too, with nobody having touched anything. With `x`, `y` and `point`
added that model would have answered a request for one frame and then
forgotten it.

**Shipped:**

- The request (`edge`, `x`, `y`, `point`, an asked-for row) and the reported
  row are held separately. The request stays readable until the user scrolls,
  which drops it, as SwiftUI's does.
- `isPositionedByUser` is set by a user scroll and nothing else — the wheel,
  the keys, the scrollbar, a drag's auto-scroll, on either axis. Writable, as
  SwiftUI's is: `true` drops an edge or offset request.
- `viewID(type:)` still answers with the row the view reports after a
  programmatic scroll and on the first frame — TUIkit's existing, deliberate
  read-back ("reading tells you where it ended up"). SwiftUI answers `nil`
  there until the user scrolls past a row. A reading SwiftUI would give is
  never different here; it is only present sooner.
- `viewID` (type-erased, `any Hashable & Sendable`) returns a *reported* row
  only when the position was made with `idType:`. A `ForEach` id is only
  `Hashable` by signature, and `Sendable` is a marker protocol no run-time cast
  can recover. An id the app passed in comes back either way.
- `x`, a `CellPoint`, and `.leading`/`.trailing` move the horizontal axis.
  These are arithmetic, not a row seek, so they need nothing from the
  row-windowing handshake that keeps `scrollTo(id:)` vertical.

**The alternative** is SwiftUI's reading exactly: `viewID` stays `nil` until
the user scrolls. That would break the `ScrollPosition` read-back tests (the
first frame and the programmatic scrolls report a row today) and take away
an answer apps can use, for no behaviour SwiftUI code depends on. I don't
recommend it.

### B-W10-2. Content margins: where TUIkit applies them, and what a scroll indicator's margin moves

*`View.contentMargins(_:_:for:)` (both), `View.contentMargins(_:for:)`,
`ContentMarginPlacement` (`.automatic`, `.scrollContent`, `.scrollIndicators`)*

Measured in SwiftUI: a `ScrollView` and a grouped `Form` apply content
margins; `List`, `Table`, `TextEditor` and a columns `Form` ignore them
entirely on macOS. TUIkit matches that list. Its grouped `Form` does not
scroll, so there the margins are padding around the sections — the picture a
scrolled-to-the-top SwiftUI form shows.

**What is a judgement:** the indicator half. SwiftUI's scrollers overlay the
content, and a margin moves an overlay. TUIkit's bar is a column (or row) of
the viewport, so:

- a vertical bar is shortened by the top and bottom margins and moved in by
  the trailing one, and the columns it moves in by come out of the content;
- a horizontal bar is shortened by the leading and trailing margins and lifted
  by the bottom one;
- margins too large for the space leave the bar one cell long rather than
  removing it;
- the "N more above / below" lines (`.scrollIndicatorStyle(.text)`, a TUIkit
  style SwiftUI code never asks for) are lines of the viewport, not a
  scroller, and do not move.

I did not measure where an overlay scroller goes under a cross-axis margin —
the probes read geometry, and an idle overlay scroller is not drawn — so
"moved in" follows `NSScrollView.scrollerInsets`, which insets a scroller
from every edge.

**The alternative** is to inset the bars along their axis only, and leave a
trailing margin to the content alone. That keeps every bar at the viewport's
edge, which a terminal user may find more natural; it is a two-line change if
you prefer it.

### B-W10-3. `safeAreaPadding` is padding, or a scroll view's content margin

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
moves in with their rows. The fuller version is B6's real safe area.

### B-W10-4. `ScrollGeometry`: the visible area excludes the bars, and a vertical view's content is as wide as it is shown

*`ScrollGeometry` and its members, `View.onScrollGeometryChange(for:of:action:)`*

Every reading matches SwiftUI's as measured (offset before the origin by the
margins, `bounds` and `visibleRect` at the offset, container less the
insets). Two numbers have no SwiftUI counterpart to measure against:

- **`containerSize` leaves out the bars.** SwiftUI's scrollers overlay the
  content, so its visible area is the frame. TUIkit's bar is a column (or row)
  of the viewport, so the area the content is seen through is the viewport
  less the bar, and less the "N more" lines where `.visible` reserves them.
  That keeps the reading apps rely on exact: `visibleRect.maxY` reaches
  `contentSize.height + contentInsets.bottom` at the bottom, and no further.
- **A vertical-only view's `contentSize.width` is the width it lays its
  content out at**, not the content's own width. The content is not measured
  across separately, and a windowed stack's drawn band is not its whole
  width; SwiftUI's would be the content's frame, which for full-width rows
  (the common case) is the same number.

**The alternative** for the first is the whole frame, bars included, which
makes `visibleRect` one cell wider than what can be seen. I don't recommend
it. For the second, a measure of the content's own width every frame a
geometry observer is attached — the cost `contentExtents` already pays for a
horizontally scrolling view. Cheap to add if a use turns up.

The observers' callbacks are a render side effect, as `onGeometryChange`'s
are, so a memo above a reporting scroll view does not keep its picture.
A/B owed on a scroll-heavy scenario with an observer attached; a scroll view
without one pays one emptiness test per frame.

### B-W10-5. Scroll phases: `.interacting` until a quarter of a second of quiet, and no velocity

*`ScrollPhase` (all five cases, `isScrolling`, `debugDescription`),
`ScrollPhaseChangeContext` (`geometry`, `velocity`), `View.onScrollPhaseChange(_:)`
(both); `CellVector`, new, as the counterpart of `CGVector`*

Measured in SwiftUI: the action runs once on appear, `.idle` to `.idle`; a
`scrollTo` without animation changes no phase; one with animation goes
`.idle` → `.animating` → `.idle`. I could not measure a mouse wheel: events
synthesized into an offscreen hosting view do not reach its scroll view.

**Shipped:** a user scroll — wheel, keys, scrollbar, a drag's auto-scroll,
either axis — makes the view `.interacting`; it returns to `.idle` once the
steps have stopped for 250 ms (fifteen 60 Hz frames, a wake requested for the
moment) and nothing is held (a scrollbar drag or auto-repeat). A terminal
reports no gesture phases, so the end of a scroll is inferred from quiet:
wheel ticks and key repeats arrive well inside 250 ms, a pause to read does
not. `.tracking`, `.decelerating` and `.animating` are never produced — there
is no touch, no momentum, and TUIkit does not animate scrolling, so an
animated `scrollTo` is a jump here and changes no phase. `velocity` is always
`nil`; SwiftUI's is optional for the same reason.

**What you might want different:**

- *The quiet interval.* Shorter makes "scrolling ended" arrive sooner and
  splits a slow wheel into several scrolls; longer the reverse. It is one
  constant (`ScrollPhase.quietNanos`).
- *A measured velocity* (lines per second over the last few steps) is cheap
  if a use turns up; I did not invent one nobody reads.
- *`.animating`* comes with animated scrolling, which is its own feature.

### B-W10-6. `scrollIndicatorsFlash` returns the view: the indicators are already showing

*`View.scrollIndicatorsFlash(onAppear:)`, `View.scrollIndicatorsFlash(trigger:)`*

A flash exists because an overlay scroller is hidden until something scrolls.
A terminal's bar, or its "N more" lines, is drawn on every frame the content
overflows, from the first — as macOS's legacy ("always show") scrollers are,
under which a flash changes nothing either. SwiftUI flashes only the
indicators configured to be visible, and those are the ones already drawn.
So both join the medium-guaranteed modifiers (`MediumGuaranteedModifiers.swift`),
with a test of the guarantee: an overflowing view's first frame shows its
indicator in either style.

**The fuller version** would be a brief highlight of the bar — its focus pulse
for half a second — to draw the eye, as a flash does. About two hours:
the bar memo is keyed on the pulse already, and the trigger needs a
per-view "last value" and a wake. I would only do it if a port asks.

### B-W10-7. `scrollTargetLayout()` returns the view

*`View.scrollTargetLayout(isEnabled:)`*

In SwiftUI the mark tells a scroll view which views to report through
`.scrollPosition(id:)` and a `ScrollPosition`; without it nothing is reported,
which is why every SwiftUI example pairs the two. TUIkit reports its windowed
stack's rows whether or not they are marked, so the mark adds nothing to the
one reader TUIkit has, and the modifier returns the view. Tested as the
pairing: seek and read-back work with the mark on the stack.

The mark's other readers are SwiftUI's view-aligned target behaviour and
`onScrollTargetVisibilityChange`, both A entries below. Shipping either means
the mark starts to matter, and the modifier becomes an environment value they
read — an hour's work, with the reader.

What SwiftUI reports and TUIkit does not is a marked *eager* `VStack`'s rows
(an existing gap of the read-back, documented on `ScrollPosition.viewID`).

### B-W10-8. The `Transaction` scroll members: what "no adjustment" suspends

*`Transaction.scrollTargetAnchor`, `Transaction.scrollContentOffsetAdjustmentBehavior`
(and `ScrollContentOffsetAdjustmentBehavior`, whose `differentShape` map entry
goes), `Transaction.scrollPositionUpdatePreservesVelocity`*

The run loop already publishes the transaction a change was made under for the
frame that renders it, so a scroll view can read all three where it decides.

- **`scrollTargetAnchor`**: preferred to a `.scrollPosition(id:anchor:)`
  modifier's anchor (SwiftUI's documentation says so); for a `ScrollPosition`
  request or a `ScrollViewProxy.scrollTo` that names an anchor of its own, the
  call's wins, and one that names none takes the transaction's. SwiftUI does
  not say which wins there; the call is the more specific statement.
- **`scrollContentOffsetAdjustmentBehavior = .disabled`** suspends a declared
  anchor's adjustments for the change: a `ScrollView`, `List` or `Table`
  following its tail does not follow, which leaves it short of the new tail
  and so releases the follow, exactly as a user scroll does (engagement is
  positional); a `List`/`Table` holding a row lets it go and holds it again
  from where the change left it. The opening placement is not an adjustment
  and is kept; an app's own write to a bound `.anchorPosition` still jumps.
  *Not covered:* a windowed `LazyVStack`'s `.anchorPosition(.row)` hold
  inside a `ScrollView` — TUIkit-only API, and the hold is in the stack files
  another lane is changing. A follow-up of an hour once that lane lands.
- **`scrollPositionUpdatePreservesVelocity`** is recorded and met by the
  medium: no scroll here has momentum, so nothing is moving for a
  programmatic change to stop or spare.

`Transaction` lives below `UnitPoint`, and every `Binding` carries one
inline, so the anchor is stored in two bytes — hundredths of the viewport,
finer than any terminal's row — and the switches share one byte with
`disablesAnimations`. A binding grows by two bytes and gains no padding (a
titled `Toggle`: 195 → 197, `ControlLayoutPaddingTests`); stored as two
`Double`s and three `Bool`s it grew by twenty-four and left five undefined.

### B-W10-9. Bounce behaviour gates the overscroll allowance

*`ScrollBounceBehavior` (`.automatic`, `.always`, `.basedOnSize`; its
`differentShape` map entry goes), `View.scrollBounceBehavior(_:axes:)`,
`EnvironmentValues.verticalScrollBounceBehavior`,
`EnvironmentValues.horizontalScrollBounceBehavior`*

The refusal review called this a cheap alias over `ScrollOverscroll`, and the
two are close but not the same: SwiftUI's bounce springs back, TUIkit's
overscroll stays (that is what makes a deliberate push readable, §1.5 of
`Scroll-anchoring.md`), and the allowance's size is TUIkit's own setting.

**Shipped:** the behaviour decides *when* the allowance applies, and
`.scrollOverscroll` keeps deciding *how far*:

- `.basedOnSize` — only while the content overflows, so content that fits
  sits still. This is the reason the modifier is written in practice, and it
  is the opt-out from your 2026-07-31 decision that a fitting view may still
  be pushed.
- `.always` and `.automatic` — whatever the content's size: TUIkit's default,
  as `.always` is SwiftUI's.

With no allowance (TUIkit's default) nothing is pushed at all, which is also
what macOS does under a mouse wheel. The allowance is vertical only, so the
horizontal value is recorded and decides nothing yet.

**The fuller version** is a real bounce: a default allowance of a line or two
under `.always`/`.automatic`, sprung back once the scroll phase returns to
idle (B-W10-5 gives the moment). Half a day, and it changes the default feel
of every scrollable, so it is yours to want.

## C. Declined without asking

### C-W10-1. `scrollInputBehavior(_:for:)` and `ScrollInputKind`

*`ScrollInputKind`, `View.scrollInputBehavior(_:for:)`*

`ScrollInputKind`'s values are watchOS's — the Digital Crown and the
double-tap hand-gesture shortcut — and the macOS SDK defines none. No macOS
source can name a kind, so none can call the modifier: declining it changes
what compiles for nobody. A terminal has neither input. What macOS code can
ask — may this view scroll at all — is `.scrollDisabled`, already the
`ScrollInputBehavior` map entry.

### C-W10-2. `ScrollView.showsIndicators`

*`ScrollView.showsIndicators`*

The stored property behind the soft-deprecated
`ScrollView(_:showsIndicators:content:)`, which TUIkit omits as it omits every
soft-deprecated spelling. `ScrollView.init`'s comment records why the
property was not kept with it: it was a second, hidden answer to the question
`.scrollIndicators(_:axes:)` answers. The property itself is not deprecated,
so this is the one arguable entry in this part: a settable `Bool`, `false`
meaning `.scrollIndicators(.hidden)` for that view, is twenty minutes if you
would rather SwiftUI code that reads or writes it compiled.

The `ScrollView.Body` map entry claimed the property was public; it never
was, and the entry now says so.

## D. Deferred to other waves

- **Scroll transitions** — `View.scrollTransition(_:axis:transition:)`,
  `View.scrollTransition(topLeading:bottomTrailing:axis:transition:)`,
  `ScrollTransitionPhase` (+ members), `ScrollTransitionConfiguration`
  (+ `Threshold` and members). The transition closure takes and returns a
  `VisualEffect`, which is Wave 12's. They also need each row's visible
  fraction against the viewport, which is A-W10-2's measurement.
- **Pinned section headers** — the `pinnedViews:` initializers of `LazyVStack`,
  `LazyHStack`, `LazyVGrid` and `LazyHGrid`, and `PinnedScrollableViews`
  (+ members). Left to the lane changing the stack initializers;
  `SwiftUI-compatibility.md` §2.8 records what pinning needs.
