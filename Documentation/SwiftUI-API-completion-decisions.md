# Completing the SwiftUI API: decisions for review

*The companion to [`SwiftUI-API-completion-plan.md`](SwiftUI-API-completion-plan.md).
That file is the plan. This one collects every point the work reached where the
call was the owner's, or where I made a call that the owner may want to revisit.
It is written to be read once, at the end of the straightforward work.*

Three parts:

- **A. Needs your decision.** Nothing has shipped for these. Each entry gives
  the options, what each costs, and my recommendation.
- **B. Shipped the safe option.** A basic, honest form is in. Each entry says
  what the fuller version or the alternative reading would be, and what it
  would cost.
- **C. Declined without asking.** Gaps I recorded in `parity-map.json` as not
  implementable, because the reason seemed unarguable. Listed so they can be
  vetoed.

Each entry names the SwiftUI symbols it covers, so `api_parity.py` output can be
traced back to it.

---

## A. Needs your decision

### A0. The eighteen refusal questions (O0–O17)

The early Wave 17 review re-examined every existing refusal in
`parity-map.json`. Its verdicts:

- 54 are wrong;
- 21 are partly wrong;
- 60 hold;
- 23 turn on a genuine design call.

Those 23 are written up, each with options and a recommendation, as O0–O17 in
[`SwiftUI-API-completion-refusal-review.md`](SwiftUI-API-completion-refusal-review.md#owner-decision).
They are not repeated here. In brief:

- **O0** The unit of a shape's path. This gates the whole Shapes cluster.
- **O1** Reduce-motion and the other accessibility preferences.
- **O2** `PhaseAnimator` and `KeyframeAnimator`.
- **O3** `CustomAnimation`.
- **O4** Matched geometry and zoom transitions.
- **O5** Materials and Glass.
- **O6** `ShadowStyle`.
- **O7** `ScrollEdgeEffectStyle`.
- **O8** APIs that are inert on macOS too: `submitLabel`, `SensoryFeedback`
  and others. This reopens `submitLabel`.
- **O9** Multi-scene apps.
- **O10** File panels.
- **O11** The `formatter:` APIs.
- **O12** `PointerStyle`.
- **O13** `Commands`, as a menu bar.
- **O14** `ControlSize`.
- **O15** `ButtonBorderShape`.
- **O16** `TextRenderer`.
- **O17** The toolbar's `.title` and `.search` items.

### A1. `\.undoManager`: who performs an undo?

*`EnvironmentValues.undoManager`*

SwiftUI hands views the window's `UndoManager`. Views register undo actions
on it, and the Edit menu's Undo/Redo (⌘Z/⇧⌘Z) performs them. A terminal app
has no Edit menu, and no key that every terminal passes through unclaimed:

- Ctrl-Z is suspend, which TUIkit already honours by drawing a final
  `.background` frame.
- Ctrl-Y is "delayed suspend" on BSD-derived ttys. In raw mode it reaches the
  app, but it is an odd key to claim.

**Options.**

1. **`nil`, always.** SwiftUI documents the value as optional, and macOS
   itself returns `nil` outside a window, so apps already handle it. Honest
   and free, but any undo support in ported code goes dark.
2. **One `UndoManager` per app, performed by a key TUIkit claims** (Ctrl-_
   is Emacs's undo; or a key the app chooses through a TUIkit-only
   modifier). Roughly a day of work:
   - the manager in the environment;
   - the key binding;
   - a status-bar hint;
   - `TextField`/`TextEditor` registering their own edits, so undo means
     something by default.
   One more thing to check: whether swift-corelibs-foundation's
   `UndoManager` is complete enough on Linux. I have not checked yet.
3. **Option 2 without the default key.** The manager exists, and the app
   wires its own key.

**Recommendation:** 2, with Ctrl-_ (which terminals send as 0x1F) and
Ctrl-Shift-_ for redo where the terminal can distinguish them. Nothing
ships until you decide.

### A2. Anchors and named coordinate spaces

*`Anchor`, `Anchor.Source`, `View.anchorPreference(key:value:transform:)`,
`View.transformAnchorPreference(key:value:transform:)`,
`GeometryProxy.subscript(_:)`, `GeometryProxy.bounds(of:)`,
`View.coordinateSpace(_:)`, `NamedCoordinateSpace`,
`CoordinateSpaceProtocol.named(_:)`, `.scrollView`, `.scrollView(axis:)`,
`CoordinateSpace.named(_:)`*

A `GeometryProxy` has to answer "where am I, in that space?" while its own
content is still being built. TUIkit renders bottom-up: a view learns where it
sits only when its ancestors composite it. `.global` already shows the
problem — nothing sets `GeometryProxy.globalOrigin`, so `frame(in: .global)`
answers the local frame and says so (`hasGlobalPosition`).

Measured in SwiftUI (W05 brief, probes L and M): an anchor resolves relative
to the reading proxy's own origin; `frame(in: .named("s"))` and
`bounds(of: .named("s"))` answer in the named view's space, and an unknown
name gives the local frame and `nil`; `.scrollView` answers in the scroll
content's space.

**Options.**

1. **G1 — markers.** A reader or an anchor site stamps a zero-content marker
   into its buffer as a floating layer, which already survives every
   combinator. The geometry owner (a preference reader, a `.coordinateSpace`
   view, a `ScrollView`, the scene root) reads the markers back out of its
   rendered subtree in its own coordinates. A proxy answers from what its
   owners found LAST frame; when that turns out wrong, the owner re-renders
   its subtree once with the corrected positions. `.global` becomes exact.
   3–4 days. The price: a correction re-render on frames where a queried
   position moved — none in steady state, but at the root it is a
   whole-frame re-render, a second source of discarded passes beside the
   app-header correction.
2. **G2 — G1 without the root correction.** `.global` keeps its documented
   fallback. About 3 days.
3. **G0 — decline the family.** Only `CoordinateSpaceProtocol` with
   `.local`/`.global` ships (it has, as the safe part).
   `anchorPreference`, named spaces and `.scrollView` geometry fail to
   compile; scroll-offset tracking leans on `onScrollGeometryChange`.

**Recommendation:** G1. It is one mechanism used five times, it closes the
`.global` hole, `onGeometryChange` needs it for named spaces, and it lets
popovers replace `PopoverAttachmentRect` with `Anchor<CellRect>.Source`.
Measure the correction rate on Stress before landing it.

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
`flipsForRightToLeftLayoutDirection(_:)` has shipped regardless: its
condition is a right-to-left environment, which cannot occur yet (B1).

## B. Shipped the safe option

### B1. `\.layoutDirection` is read-only (always left-to-right)

SwiftUI's is settable, and under `.rightToLeft` its views mirror everything
that runs along the horizontal axis:

- stacks;
- `leading`/`trailing` alignment and insets;
- text alignment;
- images that are marked to flip.

TUIkit's views do none of that yet, so a write would be accepted and
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
belongs in `Terminal-compatibility.md`, measured, before any design.

### B2. `\.legibilityWeight` is read-only (always `nil`)

SwiftUI's is settable. Under `.bold`, every piece of system text is drawn
one weight heavier. That was measured on a SwiftUI build: light→regular,
regular→bold, and bold stays bold. In SwiftUI that includes control labels.

TUIkit draws many labels without going through `Text`, so honouring it in
`Text` alone would be a partial honour, which is the shape Rule 2 forbids.

**The fuller version** is one "heavier by one step" rule applied at every
text-drawing site:

- faint→normal, normal→bold;
- `Text`, button and control labels, field contents, list chrome.

Alternatively, apply it once at the subtree's buffer, the way
`SGRColorRewrite` applies a colour effect. The rewrite is cheaper to get
complete, but it would also embolden non-text glyphs (borders, bars). That
is a reason to prefer the per-site rule.

### B3. Size classes are settable, and nothing TUIkit draws reads them

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

- They are settable channels, and nothing TUIkit draws reads them.
- macOS's text ignores both; that was measured.
- `\.dynamicTypeSize` is the same, which also answers the old refusal of
  `DynamicTypeSize`. The refusal was true about terminals and wrong about
  the API, because macOS reads `.large` and ignores writes for text too.

### B4. `DynamicProperty.update()` does not write back

An app's own property wrapper conforms to `DynamicProperty`, and the
properties inside it work as they would on the view: `@State` is kept per
view and `@Environment` reads where the view sits. `update()` runs before
every `body`.

One difference from SwiftUI. SwiftUI writes back whatever `update()`
changes in the wrapper's own stored values. TUIkit calls it on the value the
view holds, and that value is not the one `body` then reads. So a change made
in `update()` has to go into a `@State`, or into an object held by reference,
to be seen. Reading values, and refreshing a reference-typed cache, behave
the same in both frameworks; those are what nearly every `update()` I know of
does.

**The fuller version** would write the property back into the view before
`body`. The property walks find properties through `Mirror`, which is
read-only, so this needs the stdlib's reflection SPI
(`_forEachFieldWithKeyPath`) to get a writable key path per stored property.
It touches the hottest walk in the framework.

Cost: about half a day, plus a measurement. I would only do it if real code
turns up that needs it.

### B5. Button styles: SwiftUI's names, and what `.plain` now means

SwiftUI's built-in button styles now exist under SwiftUI's names, as
`PrimitiveButtonStyle`s, and TUIkit's own `.default` and `.primary` are gone.
The SwiftUI names were already documented as equivalents, but
`.buttonStyle(.bordered)` did not compile. The mapping is mine:

| Style | Draws | Note |
|---|---|---|
| `.automatic`, `.bordered` | the bracketed button | as on macOS, where automatic resolves to bordered |
| `.borderedProminent` | the bracketed button, bold, in the accent colour | was `.primary` |
| `.borderless` | no caps, accent label | **was TUIkit's `.plain`** |
| `.plain` | no caps, ordinary text colour | SwiftUI: "doesn't style or decorate its content" |
| `.link` | accent, underlined, focus in the words | like `Link` |
| `.accessoryBar` / `.accessoryBarAction` | plain / bordered | TUIkit draws no accessory bars of its own |

**What you might want to revisit: `.plain` changed meaning.**
- TUIkit's old `.plain` tinted its label with the accent colour. SwiftUI's
  doesn't, and SwiftUI's `.borderless` is the tinted one.
- Every framework call site that used `.plain` now uses `.borderless`, so
  nothing TUIkit draws changed: disclosure and outline headers, the colour
  pickers, client pickers, the Stress menu bar, and the Example demo of
  "links".
- An app that wrote `.plain` sees its labels in the ordinary text colour.
- If you'd rather keep `.plain` tinted, the cost is a known divergence from
  SwiftUI. That is a one-line change.

**Custom primitive styles follow SwiftUI exactly.**
- The style's body *is* the button. TUIkit registers no focus stop, keys or
  click for it, because the body decides how the button is operated.
- A body that builds `Button(configuration)` gets one ordinary button, drawn
  in the style the custom one was applied over.
- A body that draws only the label makes a control that nothing can operate.
  That is SwiftUI's semantics; it is also the one place a TUIkit style can
  produce a control the keyboard cannot reach.
- The alternative is for TUIkit to keep the focus and keys itself and let the
  body draw. That costs a second code path, and two focus stops whenever the
  body also builds a `Button`. I don't recommend it.

**Declined (C):** `.glass`, `.glassProminent` and `.glass(_:)` join the
existing `Glass*` family rule.

### B6. `safeAreaInset` puts the bar beside the view; there is no safe area

*`View.safeAreaInset(edge:alignment:spacing:content:)` (both edge types),
`View.safeAreaBar(edge:alignment:spacing:content:)` (both); still refused:
`View.safeAreaPadding` ×3, `View.ignoresSafeArea(_:edges:)`, `SafeAreaRegions`,
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

`safeAreaPadding` comes with Wave 10's `contentMargins`: for non-scrolling
content it is padding, and for a scroll view it is a content margin.

## C. Declined without asking

### C1. `CGPoint`, `CGSize` and `CGRect` as `Animatable`

*`CGPoint.AnimatableData`, `CGSize.AnimatableData`, `CGRect.AnimatableData`*

This is a compiler wall, not a judgement. On Apple platforms, SwiftUICore's
own extensions of the CoreGraphics types are visible to any module that
imports Foundation, through a cross-import overlay. That is the same overlay
`Collection+Offsets.swift` already works around. SwiftUICore's
`AnimatableData` typealias on each type is found before any witness TUIkit
could give, so `extension CGPoint: Animatable` does not compile on macOS. I
tried with and without an explicit typealias.

`CGFloat` *is* conformed, because there the wall has a door. An app's ported
`Animatable` type with `CGFloat` data compiles and animates, and so does
`AnimatablePair<CGFloat, CGFloat>`. What stays ambiguous on macOS is calling
the extension methods directly on a concrete value (`x.interpolated(…)`).
That call never linked before either.

### C2. `CGPoint.applying(_:)`, `EdgeInsets.inset(by:edges:)`, `EdgeInsets.init(_:)`

- The first two take types that were already declined: `ProjectionTransform`
  and `RectangleCornerInsets`.
- The third converts AppKit's `NSDirectionalEdgeInsets`, whose values are
  points. The conversion would need an invented point-to-cell scale.

### C3. `AttributeDynamicLookup`

This is folded into the existing `AttributeScopes*` family rule, whose reason
it shares.

**That family is itself on the Wave 17 re-examination list.** SwiftUI's
attribute scope carries a foreground colour, a background colour, an
underline and a strikethrough, all of which a cell grid has. So
`Text(AttributedString)` may well be implementable.
