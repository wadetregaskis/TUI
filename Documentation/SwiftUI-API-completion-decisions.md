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
- **O5** Materials and Glass (A41 lists the material symbols waiting on it).
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
- **O16** `TextRenderer`, with `View.textRenderer(_:)` and `Text.customAttribute(_:)`.
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

**Wave 11 adds four symbols to the same question:**
`View.multilineTextAlignment(strategy:)`, `View.writingDirection(strategy:)`,
`Text.AlignmentStrategy` and `Text.WritingDirectionStrategy`. Each strategy
chooses between the layout direction and a paragraph's own writing
direction. TUIkit lays every paragraph out left to right, so the two agree
except on a right-to-left paragraph. There, `.writingDirectionBased` and
`.contentBased` would right-align a Hebrew line in SwiftUI and left-align it
here. Shipping them before right-to-left would be a quiet lie for exactly
the text they exist for, so they wait with this entry.

### A4. Speak the kitty keyboard protocol where the terminal does?

*`KeyPress.Phases.up` (and a real `.repeat`), `View.onModifierKeysChanged(mask:initial:_:)`,
`View.modifierKeyAlternate(_:_:)`; and, as by-products, `EventModifiers.capsLock`
and `.numericPad`, and `KeyboardShortcut.Localization`'s remapping*

Four of this wave's gaps share one cause. A terminal's legacy key encoding
reports a key going down and nothing else:

- no release;
- no repeat flag;
- no modifier pressed on its own;
- no lock state.

The kitty keyboard protocol reports all of those, once an app asks for it with
`CSI > flags u`. Flag 2 reports event types (press, repeat, release). Flag 8
reports every key as an escape code, including the modifiers themselves. kitty,
Ghostty, WezTerm and foot implement it, and recent iTerm2 and Alacritty
releases say they do. That is from their documentation, not measured here.
Apple Terminal does not.

Until this is decided:

- `.up` is absent, and every press is `.down` (B7).
- `onModifierKeysChanged` and `modifierKeyAlternate` are absent: on a legacy
  terminal they could never fire.
- Caps Lock and the numeric pad never match (the `EventModifiers.command`
  precedent).

**Options.**

1. **Stay on the legacy encoding.** Free. The four APIs stay absent for good,
   on every terminal, including the ones that could honour them.
2. **Negotiate flags 1 + 2 + 8 where the terminal answers the `CSI ? u`
   query, and keep the legacy decoder for the rest.** Roughly three to four
   days:
   - the negotiation and its teardown on suspend, exit and crash, beside the
     modes `Terminal` already restores;
   - a `CSI … u` decoder;
   - `KeyEvent` gaining a phase, and every consumer learning to ignore
     releases;
   - a per-terminal survey into `Terminal-compatibility.md`.

   It also fixes things outside this wave. Ctrl-H, Ctrl-I, Ctrl-J, Ctrl-M and
   Ctrl-[ become deliverable shortcuts. Shift on a printable key becomes a real
   bit. A held key's repeats become identifiable.
3. **Option 2 with flag 1 only (disambiguate).** About a day and a half. Fixes
   the C0 collisions and nothing in this wave.

Under option 2 a second question follows, and it is about the rule rather
than the code. Should `.up`, `onModifierKeysChanged` and `modifierKeyAlternate`
**compile everywhere** and fire only where the protocol is spoken, documented
per terminal as `EventModifiers.command` is? Or should they stay absent, since
on Apple Terminal they would be silent?

**Recommendation:** option 2. On the second question: compile everywhere, with
a runtime query (a `\.keyboardReportsReleases`-style environment value) so an
app can offer its own fallback. Leaving the APIs absent would deny them to
every terminal that can honour them in order to protect the one that cannot.

### A5. `onInteractiveResizeChange`: synthesise a live resize from `SIGWINCH`?

*`View.onInteractiveResizeChange(_:)`*

macOS calls the action with `true` when the user starts dragging a window edge
and `false` when they let go. Its documented use is to throttle expensive
drawing during the drag.

A terminal sends `SIGWINCH` once per size change and says nothing about a
drag. Dragging a terminal window's edge sends a burst of them. So do a font
size change and a tmux pane resize, as one or a few.

**Options.**

1. **Decline.** A terminal has no notion of a live resize, so nothing can say
   when one begins or ends.
2. **Synthesise it.** `true` at the first `SIGWINCH` after a quiet period;
   `false` once none has arrived for about 200 ms. That is the same kind of
   inference the dispatcher already makes for double-clicks, which a terminal
   does not report either. Roughly half a day: the signal path already wakes
   the run loop, and the quiet-period timer needs a wake of its own.

**Recommendation:** 2. A TUI re-lays out the whole screen on every
`SIGWINCH`, which is exactly the cost the API exists to manage. It would be
documented as "a burst of resizes", because a font-size change counts as
one.


*Wave 10's entries (A6–A12, B23–B31, C6–C7): SwiftUI behaviour quoted as *measured* was measured on macOS 15 with an offscreen `NSHostingView`; the probes are in the session notes, `w10/probe`.*

### A6. Scroll target behaviours: SwiftUI's protocol, or keep `ScrollGranularity`?

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
`velocity` the step's direction and rate (a `CellVector`, B27), and
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

### A7. Scroll visibility needs a way to find a view inside the scroll content

*`View.onScrollVisibilityChange(threshold:_:)`,
`View.onScrollTargetVisibilityChange(idType:threshold:_:)`; and the scroll
transitions, which need the same reading (`View.scrollTransition(_:axis:transition:)`,
`View.scrollTransition(topLeading:bottomTrailing:axis:transition:)`,
`ScrollTransitionConfiguration`, `ScrollTransitionPhase`), now that Wave 12's
`VisualEffect` gives their bodies something to return*

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

### A8. `ScrollAnchorRole.alignment`, and what the unlabelled anchor already means

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

### A9. `scrollContentBackground(_:)`: `.visible` has to paint something

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

### A10. `scrollClipDisabled(_:)`: how much may draw outside the viewport?

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

### A11. `scrollDismissesKeyboard(_:)` joins O8

*`View.scrollDismissesKeyboard(_:)`, `ScrollDismissesKeyboardMode` (+ `.automatic`,
`.immediately`, `.interactively`, `.never`),
`EnvironmentValues.scrollDismissesKeyboardMode`*

It is about the software keyboard, which macOS does not have either, so on
macOS every mode is inert — exactly refusal-review O8's question. Under O8's
recommended (b) it ships as a recorded, documented-inert value, as macOS's is;
under (a) it is declined with `submitLabel`. Nothing to decide here apart from
O8.

### A12. The scroll edge effects join O7

*`View.scrollEdgeEffectHidden(_:for:)`, `View.scrollEdgeEffectStyle(_:for:)`*

They style content passing under a bar, and nothing passes under a bar here
(B6). Refusal-review O7 already asks whether to ship them with the safe-area
design; these two modifiers are that question's modifiers.

### A13. Text selection: draw TUIkit's own, or leave it to the terminal?

*`View.textSelection(_:)`, `TextSelectability`, `EnabledTextSelectability`,
`DisabledTextSelectability` (`.enabled`, `.disabled`, `allowsSelection`)*

In SwiftUI, `.textSelection(.enabled)` lets the user select a `Text`'s
characters and copy them; `.disabled`, the default, does not. A terminal
already selects text itself, but only when the app is not reporting the
mouse. TUIkit reports it whenever an app has anything clickable, and then
most emulators select only with a modifier held (Option in iTerm2 and
Terminal.app, Shift in xterm and kitty). That means neither value can be
honoured as written today. `.disabled` cannot stop the emulator's own
selection, and `.enabled` does not make selection reachable without the
modifier.

**Options.**

1. **TUIkit's own selection.** A drag over text that allows it paints a
   selection (the inverted-highlight rules apply), and Copy (⌘C where the
   terminal forwards it, else Ctrl-Shift-C; plus a context-menu item) puts
   the characters on the clipboard through the existing clipboard path
   (OSC 52, else `pbcopy`/`wl-copy`/`xclip`). The keyboard route is required
   too (see the no-mouse-only rule): Shift-arrows from a focused selectable
   text. `.disabled` then means TUIkit draws no selection; the emulator's
   modifier-drag still works, which is the terminal's, not the app's. About
   3–4 days, mostly the keyboard route and the hit-testing of wrapped lines.
2. **Ship `.enabled` as "selectable by the terminal" and omit `.disabled`.**
   Honest about what happens, but a modifier-drag is not what a SwiftUI
   developer means by selectable, and the default would be the one value
   that does not compile.
3. **Decline both** with a map entry naming the emulator's own selection.

**Recommendation:** 1, after the rest of the batch. It is the only option
under which SwiftUI source means what it says.

### A14. String tables and bundles for localized text

*`Text.init(_:tableName:bundle:comment:)`, and the same parameters wherever
SwiftUI takes a `LocalizedStringKey`*

TUIkit's localization is a registered dictionary per language, and
`LocalizedStringKey`'s note says the parameters are absent because there
are no tables or bundles for them to name. That holds for TUIkit's own
strings. An app ported from SwiftUI arrives with `Localizable.strings` /
`.xcstrings` in its bundle, though.

**Options.**

1. **Look the key up in `bundle`'s `tableName` table through Foundation**
   (`Bundle.localizedString(forKey:value:table:)`, which swift-corelibs
   implements for `.lproj/*.strings`), after the registered dictionary
   misses. `.xcstrings` is compiled to `.strings` only by Xcode, so a SwiftPM
   app would ship `.strings` or register a dictionary. Half a day plus tests
   on Linux.
2. **Keep the parameters absent.**

**Recommendation:** 1. It makes the common ported call compile and work, and
it costs nothing for apps that never pass a table.

### A15. Asset catalogues: named colours and images

*`Color.init(_:bundle:)`, `Image.init(_:bundle:)`, `Image.init(_:bundle:label:)`,
`Image.init(decorative:bundle:)`*

Both load from an asset catalogue, which only Xcode compiles. A SwiftPM
executable, which every terminal app is, has none (the `image:` overloads are
declined on exactly this ground, in the map's `ImageResource` family).

**Options.**

1. **Read the uncompiled catalogue** if the app copies an `.xcassets`
   folder as a resource: `Name.colorset/Contents.json` for a colour (with
   its light and dark variants chosen by `\.colorScheme`), and
   `Name.imageset`'s largest file for an image. About a day.
2. **Look for a plain file** (`Name.png`, `Name.jpg`) among the bundle's
   resources, for images only. An hour.
3. **Decline** both with the same reason as the `image:` overloads.

**Recommendation:** 2 for images, 3 for colours: a named colour without its
catalogue has nothing to read, and a theme's palette is the terminal app's
way of naming colours.

**Shipped since, as the basic:** option 2 for the three `Image` initialisers
(`Image+Bundle.swift`). The open question is whether to add option 1 on top,
and what to do with `Color.init(_:bundle:)`.

### A16. Colours that resolve themselves, and HDR

*`Color.init(_:)` for a `ShapeStyle & Hashable` whose `Resolved` is
`Color.Resolved` or `Color.ResolvedHDR`; `Color.ResolvedHDR` and its
members; `Color.resolveHDR(in:)`, `Color.headroom(_:)`,
`Color.exposureAdjust(_:)`*

`Color.Resolved`, `resolve(in:)` and the component initialisers have
shipped. Two things remain.

- **A custom colour provider.** SwiftUI's `Color(MyStyle())` defers to the
  style at every resolve. TUIkit's `Color` is five bytes with no padding:
  every `Text` carries two, every cell's run carries them, and the value
  hash reads them as plain words. A provider case would hold an existential
  (40 bytes), growing every one of those, or an index into a registry, which
  is a singleton. Resolving the provider once at `init` against a default
  environment would be the quiet lie the parity rules forbid.
- **HDR.** A terminal is SDR, so a headroom cap is always met
  (`headroom(_:)` would return the colour unchanged, honestly), and
  `ResolvedHDR` is a value type that could ship as data.
  `exposureAdjust(_:)` brightens by stops, though, and a palette role or a
  terminal slot has no numbers until it is painted, so it cannot be applied
  at `init`.

**Options.** (a) Decline the provider, ship `ResolvedHDR`, `resolveHDR(in:)`
and `headroom(_:)`, and decline `exposureAdjust(_:)`. (b) Decline all of it.
(c) Grow `Color` for the provider.

**Recommendation:** (a). All of these are macOS 26 APIs (the HDR half could
not even be probed on this machine's macOS 15), and they are rare in ported
code.

### A17. `preferredColorScheme(_:)`

*`View.preferredColorScheme(_:)`, `PreferredColorSchemeKey` (`Value`,
`reduce(value:nextValue:)`)*

The compatibility doc (§2.5) keeps this out on purpose. A terminal's look is
a palette, and the write half of `\.colorScheme` is `.palette(_:)`. The
Wave 17 review never saw it, because it was absent rather than mapped.

**Options.**

1. **Keep it absent**, and add a map entry pointing at §2.5.
2. **Let it choose a palette's light or dark variant.** That needs palettes
   to come in pairs. The built-in `SystemPalette`s would need a light twin
   each, and a custom palette would declare its twin. The preference then
   flows up to the scene, as SwiftUI's does, and picks between the pair. Two
   to three days, mostly the light palettes' contrast work.

**Recommendation:** 1 for this batch, 2 only if light palettes are wanted for
their own sake.

### A18. Apple-only public API behind `#if canImport`: allowed or not?

*Policy, with these symbols waiting on it: `AppStorage`/`SceneStorage`'s
`store: UserDefaults` spellings, `View.defaultAppStorage(_:)`,
`Scene.defaultAppStorage(_:)`; and, if allowed, Core Data's `FetchRequest`
family (declined in the map today)*

The Wave 17 review treats "no Apple-only public API surface" as settled (its
`SectionedFetchRequest` note). The batch has not kept to it:

- **Wave 7** shipped `onDrag`, `onDrop(of:…)`, `DropDelegate`, `itemProvider`
  and the `onCopyCommand`/`onCutCommand` forms that take `NSItemProvider`,
  behind `#if canImport(UniformTypeIdentifiers)`.
- **Wave 13** shipped `Color(cgColor:)`, `Color(nsColor:)`, `NSColor(_:)` and
  `Color.Resolved.cgColor`, behind `canImport(AppKit)`/`(CoreGraphics)`.

Each is honoured where it exists, and absent elsewhere. A Linux build simply
does not offer it, so it cannot compile there and do nothing.

**Options.**

1. **Allow it, behind `canImport`, where the feature is honoured on Apple
   platforms.** Then `store: UserDefaults` and `defaultAppStorage(_:)` ship
   (`UserDefaultsStorage` gains an `init(_ defaults: UserDefaults)`), and Core
   Data's `FetchRequest` becomes possible for macOS-only apps (a few days).
2. **Forbid it.** Remove the Wave 7 and Wave 13 surfaces above, and keep the
   storage spellings TUIkit's own (`StorageBackend`), with
   `defaultAppStorage(_:)` taking one. A ported `@AppStorage(…, store:
   UserDefaults(…))` then fails to compile.
3. **Allow bridges and value conversions only** (colours, item providers),
   not frameworks (Core Data).

**Recommendation:** 1, with "honoured where it exists" as the test, which is
the rule the batch has been following in practice.
`defaultAppStorage(_:)` also needs `@AppStorage` to resolve its store from
the environment at render, through a nested `@Environment`; that part is
half a day whichever option is chosen.

*Wave 9's entries (A19–A25, B34–B41, C9): SwiftUI's behaviour is from its own doc comments unless an entry says it was measured.*

### A19. Let the reader move a sheet between its detents, and reach the page behind it?

*`View.presentationDragIndicator(_:)`, `PresentationContentInteraction.resizes`,
`PresentationBackgroundInteraction.enabled`,
`PresentationBackgroundInteraction.enabled(upThrough:)`*

Four symbols that only mean something if a sheet can be resized by the person
using it, or left half-open while they work in the page behind it. Neither is
possible here today: a multi-detent sheet changes size only through its
`selection:` binding (there is no grabber to drag), and the page behind any
presentation is drawn as an inert, dimmed backdrop under a throwaway focus
manager. What shipped are the values that describe that:
`PresentationContentInteraction.automatic`/`.scrolls` and
`PresentationBackgroundInteraction.automatic`/`.disabled`, each modifier
returning the view unchanged. The four above are left out, so they fail to
compile. On macOS they are probably inert too (sheets are window-modal there,
and the drag indicator is an iOS affordance), but I could not measure that with
an offscreen hosting view.

**Options.**

1. **Leave them out.** Free; the status quo.
2. **A grabber, by keyboard and pointer.** A `▔▔▔` row on top of a
   multi-detent sheet when `presentationDragIndicator(.visible)` (or
   `.automatic` with more than one detent), dragged with the pointer or moved
   by a key pair (Ctrl-Up/Ctrl-Down, say) to the next detent, writing the
   `selection:` binding when there is one. `.resizes` then means the wheel
   over the sheet resizes it before scrolling it. About a day with tests; the
   key pair has to be checked against the terminals' own bindings
   (`Terminal-compatibility.md`).
3. **Option 2, plus a live page behind a sheet** for `.enabled(upThrough:)`:
   the page renders live rather than as a backdrop, the sheet stops grabbing
   input below the given detent, and Tab crosses between them. That changes
   the presentation model's central rule (a presentation owns the keyboard),
   so it is two to three days and needs its own design note.
4. **Follow O8** if you rule there that APIs inert on macOS ship as inert.

**Recommendation:** 1 for now; 2 if detented sheets turn up in real apps.

### A20. `presentationSizing(_:)`: what are `.form` and `.page` in cells?

*`PresentationSizing` (`.automatic`, `.fitted`, `.form`, `.page`,
`fitted(horizontal:vertical:)`, `sticky(horizontal:vertical:)`,
`proposedSize(for:context:)`), `AutomaticPresentationSizing`,
`FittedPresentationSizing`, `FormPresentationSizing`, `PagePresentationSizing`
(and their `proposedSize(for:context:)`), `PresentationSizingRoot`
(`sizeThatFits(_:)`), `PresentationSizingContext`, `View.presentationSizing(_:)`*

macOS 15 sizes a sheet by one of these: `.fitted` is the content's ideal size,
`.form` "appropriate for forms", `.page` "roughly the size of a page of paper",
and `.automatic` is `.form.fitted(horizontal: false, vertical: true)` there. A
custom sizing proposes a size from the content's (`PresentationSizingRoot`), and
`sticky` keeps the largest size seen in an axis.

A terminal sheet today is `.fitted` exactly: the content is the sheet, and
only a detent changes its height, by handing the height to the content's
outermost box (`sheetDetentHeight`).

**Options.**

1. **Leave them out** (the status quo): sizing code fails to compile.
2. **Ship the family.** `.fitted` is today's sheet; `.form` proposes
   `min(64, width)` columns (about macOS's 540-point form sheet), `.page`
   `min(96, width)` columns by the content area's height; `.automatic` follows
   macOS (form width, fitted height). A proposal reaches the sheet's box the
   way a detent does, which needs a width twin of `sheetDetentHeight`
   consumed by `Dialog`, `Panel`, `Card` and `.border()`; `sticky` keeps the
   largest size in the presenter's state. A day with tests; it is a drawing
   change for no sheet that does not ask.
3. **Option 2 with `.automatic` left at `.fitted`**, so no existing sheet
   changes width.

**Recommendation:** 3. The numbers in 2 are mine and are the part to veto.

### A21. Compact-size-class adaptation and `preferredCompactColumn`

*`PresentationAdaptation` (`.automatic`, `.none`, `.popover`, `.sheet`,
`.fullScreenCover`), `View.presentationCompactAdaptation(_:)`,
`View.presentationCompactAdaptation(horizontal:vertical:)`,
`NavigationSplitView.init(preferredCompactColumn:…)` (all four)*

All of these say what to do in a compact size class: present a popover as a
sheet, show which split view column on top once the split collapses into one.
macOS is never compact, so on a Mac they are inert; TUIkit's size classes are
`.regular` unless an app sets them, and nothing TUIkit draws reads them (B3) —
the split never collapses and a popover never adapts.

**Options.**

1. **Leave them out** until B3 is decided.
2. **Ship them inert**, as macOS has them — under O8's option (b), citing
   the size classes never being compact here.
3. **Make them real:** a popover or sheet adapts by `PresentationAdaptation`
   when the environment's size class is compact (`.automatic` adapting a
   popover to a sheet, as iOS does), and a split view collapses into a stack
   showing `preferredCompactColumn` in a compact horizontal class. The
   adaptation is small (the popover presenter delegates to the sheet or cover
   presenter); the collapse is not (a split that becomes a stack keeps its
   columns' state and focus sections) — two days together. It only matters if
   B3 makes a narrow terminal compact.

**Recommendation:** decide with B3 and O8: 2 if O8 is (b) and B3 stays
"regular", 3 if B3 makes narrow terminals compact.

### A22. `DismissBehavior` waits on O9

*`DismissBehavior`, `.interactive`, `.destructive`, and (from Wave 12) `Transaction.dismissBehavior`*

It qualifies `dismissWindow` (`withTransaction(\.dismissBehavior, .destructive)`
closes a window even with a sheet up on it). `dismissWindow` is in the window
family the map declines, which O9 of the refusal review reopens. If O9 goes
(b) — secondary scenes as covers stacked over the main one — `.destructive`
means closing such a cover with its own presentations still up, and
`.interactive` refusing to; under (a) or (c) the type has nothing to qualify
and joins the decline.

### A23. `matchedTransitionSource` waits on O4

*`View.matchedTransitionSource(id:in:)`,
`View.matchedTransitionSource(id:in:configuration:)`*

The source half of the `.zoom` navigation transition, which O4 (matched
geometry and zoom transitions) covers. `NavigationTransition` and `.automatic`
shipped (the stack's own transition); `.zoom` and these two follow O4.

### A24. `presentationCornerRadius(_:)` waits on O0/O15

*`View.presentationCornerRadius(_:)`*

A sheet's corner radius. A terminal's corners are box-drawing glyphs, so the
honest reading is a choice of corner — `0` square (`┌`), anything larger
rounded (`╭`), `nil` the appearance's — applied to the sheet's box. But the box
is drawn by the content (a `Dialog`, a `Panel`), not by the presenter, and what
a radius means in cells is the question O0 (shapes) and O15
(`ButtonBorderShape`) are already asking. It should be answered once, there.

### A25. `searchSelection(_:)` waits on A13

*`View.searchSelection(_:)`*

It binds the search field's `TextSelection`. That type, and whether TUIkit
draws its own selection at all, is A13 (text selection) in the main decisions
doc. Once `TextField` takes a selection binding, this is a few lines on the
searchable's field.

### A26. The scene-level dialog modifiers and optional scenes wait on O9

*`Scene.dialogIcon(_:)`, `Scene.dialogSeverity(_:)`,
`Scene.dialogSuppressionToggle(_:isSuppressed:)` and `(isSuppressed:)`,
`SceneBuilder.buildOptional(_:)`, `SceneBuilder.buildLimitedAvailability(_:)`;
and with them O9's settings scene: `Settings`, `SettingsLink`,
`DefaultSettingsLinkLabel`, `OpenSettingsAction`, `\.openSettings`*

SwiftUI's examples apply the dialog modifiers to an `AlertScene`, and the two
builder methods exist for `if #available` around a scene among others. Both
need more than one scene, which TUIkit's `SceneBuilder` does not build: that is
O9 of the refusal review.

**Options.**

1. **Under O9 (b) or (c):** ship the dialog modifiers as scene environment
   writes, reaching an `AlertScene` and the alerts the scene's views present.
   That is half an hour, on top of `Scene.environment(_:_:)`. Under (b), the
   builder methods come with the variadic `buildBlock`.
2. **Under O9 (a):** decline all six with the window family.

**Recommendation:** follow O9. The dialog modifiers could ship today as
environment writes, but whether SwiftUI's reach a view's alert, and not only
an `AlertScene`, cannot be measured offscreen. Alerts are modal panels.

### A27. Pixel effects: transforms, masks and `drawingGroup` (Wave 16)

*`View.scaleEffect(_:anchor:)`, `View.scaleEffect(x:y:anchor:)`,
`View.rotationEffect(_:anchor:)`, `View.rotation3DEffect(_:axis:anchor:anchorZ:perspective:)`,
`View.projectionEffect(_:)`, `View.transformEffect(_:)`, `View.mask(alignment:_:)`,
`View.drawingGroup(opaque:colorMode:)`; and, waiting on refusal-review items
already, `View.clipShape(_:style:)` and `View.contentShape(_:eoFill:)`/`(_:_:eoFill:)`
(O0), `View.shadow(color:radius:x:y:)` (O6)*

Wave 16 shipped what a cell grid keeps honestly: `clipped(antialiased:)` (the
cut `ScrollView` and `List` already made) and `compositingGroup()` (a guarantee
the compositor keeps). Blur, blend modes, luminance to alpha and the background
extension effect joined the map's per-pixel shading family. The rest is yours.

**Transforms.** A glyph cannot be scaled or turned, and an affine transform
of a cell grid is not a cell grid.

1. **Decline all six.** `scaleEffect(isPressed ? 0.95 : 1)` in ported code then
   fails to compile, and the developer removes it. Free.
2. **`scaleEffect` as the `.scale` transition draws it**, a reveal from the
   anchor, with `rotationEffect` and the rest declined. A scale of 0.95 then
   draws as 1 (nothing to reveal), which is the silent no-op rule 2 forbids, so
   this only makes sense with a threshold. Half a day.
3. **Raster content only:** a scaled or quarter-turned `Image` is resampled.
   The receiver is any view, so the type system cannot keep this to images.
   Text would draw unchanged. That is a no-op again. A day.

**`mask(alignment:_:)`.** Masking by another view's alpha can be honoured at
cell granularity: a cell where the mask draws (a glyph or a background) keeps
the content, at the mask colour's alpha through an opacity region, and the
rest is cleared to what is behind. Choosing that coverage rule is the decision
("a space with no background masks out" is the one that would surprise). Half
a day.

**`drawingGroup(opaque:colorMode:)`.** In SwiftUI it flattens the view into an
offscreen image before display. Here every view already composites as one
picture, as for `compositingGroup()`. `opaque` is a promise by the caller.
`colorMode: .linear` asks for linear-light blending, which TUIkit's encoded-sRGB
blend does not do.

1. **Ship it as `compositingGroup()`**, honouring `.nonLinear`, the default,
   and documenting `.linear` and `.extendedLinear` as blended non-linearly.
2. **Decline it.**

**Recommendation:** transforms (1); mask, the cell-coverage rule; drawingGroup
(1), since nearly every use is the argument-free performance hint.

### A28. Toolbars (Wave 15)

*44 symbols: `View.toolbar(content:)`, `toolbar(id:content:)`, `ToolbarItemGroup`,
`ToolbarSpacer`, `ToolbarTitleMenu`/`toolbarTitleMenu(content:)`,
`toolbarRole(_:)`/`ToolbarRole`, `toolbarTitleDisplayMode(_:)`,
`toolbarBackground(_:for:)`, `toolbarBackgroundVisibility(_:for:)`,
`toolbarColorScheme(_:for:)`, `toolbarVisibility(_:for:)`, `toolbarItemHidden(_:)`,
`ToolbarLabelStyle` and `\.toolbarLabelStyle`, `contentToolbar(for:content:)`,
`ContentToolbarPlacement`, `LabeledToolbarItemGroupContent`, the customization
family (`CustomizableToolbarContent`, `ToolbarCustomizationBehavior`,
`ToolbarCustomizationOptions`), `SpacerSizing` (for `ToolbarSpacer`),
`tabBarMinimizeBehavior(_:)`, and the window toolbar styles
(`DefaultWindowToolbarStyle`, `ExpandedWindowToolbarStyle`,
`UnifiedWindowToolbarStyle`, `UnifiedCompactWindowToolbarStyle`), which style
a window's toolbar the terminal owns and follow option 1 whatever is chosen*

The compatibility doc (§2.6) makes the toolbar a deliberate divergence. A
terminal's chrome is the one-line status bar, and the map renames
`ToolbarItem` to `StatusBarItem`. That leaves the commonest SwiftUI idiom,
`.toolbar { ToolbarItem(placement: .primaryAction) { Button(…) } }`, failing to
compile in every ported app.

**Options.**

1. **Keep §2.6.** Decline the 44 with the `Commands` family's reason. Free.
2. **Host toolbar content in the chrome TUIkit already draws.** Navigation,
   principal and primary-action placements become buttons on
   `NavigationStack`'s bar row (its root, which has no bar today, would gain
   one when it has items), or on the app header outside a stack. Status and
   bottom-bar placements go to the status bar row. The buttons are a focus
   section. Visibility, background and title-menu modifiers act on that row.
   `toolbar(id:)` customisation and `ToolbarLabelStyle` are declined.
   Three to four days, most of it the root bar and focus.
3. **Option 2 with customisation:** a sheet that reorders and hides items,
   saved by the `id:`. Another two days.

**Recommendation:** 2. It reverses §2.6's "should NOT change", which is why
it is yours. `StatusBarItem` stays as the terminal-native complement.
`ToolbarTitleDisplayMode` and `tabBarMinimizeBehavior` follow O8, and the
toolbar's `.title`/`.search` items follow O17.

*Wave 8a's entries (A29–A31, B44–B47, C10): SwiftUI's behaviour was measured on macOS 15.8, built against the macOS 26.2 SDK, with an offscreen `NSHostingView`; the probes are in the session notes, `w08a/probe`.*

### A29. Should a table look like SwiftUI's by default — borderless and striped?

*`AlternatingRowBackgroundBehavior.automatic`, `AutomaticTableStyle`,
`TableStyle.automatic`*

`.alternatingRowBackgrounds(_:)` shipped for tables and lists alike:
`.enabled` stripes every other row with the tint a striped `ListStyle` has
always drawn (the accent at 15% over the page), `.disabled` never stripes.
`TableStyle` shipped too: `.bordered` is the rounded box every TUIkit table
has always drawn, `.inset` draws no border.

Both have an `.automatic`, and SwiftUI's macOS answers differ from TUIkit's
look. Measured on macOS 15.8 (built against the macOS 26.2 SDK): a plain SwiftUI `Table`, `.automatic` and
`.inset` alike, is an `NSTableView` of style `.inset` in a scroll view with no
border, with `usesAlternatingRowBackgroundColors` on; `.bordered` is style
`.fullWidth` in a scroll view with a line border, striped too. Stripes follow
`.alternatingRowBackgrounds(.disabled)` under either style.

Shipped: `.automatic` is bordered and unstriped — every TUIkit table keeps
its look, and SwiftUI source that names a style or asks for stripes gets
them.

**Options.**

1. **Bordered and unstriped by default** (shipped). The divergence is the two
   defaults alone. Free.
2. **SwiftUI's default: inset and striped.** Every table without a style
   changes: the border goes, which gives the rows two lines and moves every
   click target a line up and a cell left; half the rows draw a background,
   so frames grow by a background SGR per striped row (row memos keep them,
   but a churning table pays), under a tint palettes were tuned without.
   Golden and render tests that read a table's bytes need re-baselining.
   Half a day, most of it the tests.
3. **Inset by default, unstriped.** The border is where a terminal table's
   look differs most from a window's: a box around a table in a window of
   boxes reads as one more panel. The two lines it frees are worth the most
   on a short terminal. Same test cost as 2, without the stripe's.

**Recommendation:** 1. A terminal's rows are a single line of text on a fixed
grid, where a reader's eye does not drift between rows the way it does across
a wide window, and a stripe the palette did not plan for is a cost every theme
pays; the border is what tells a table from the text around it when nothing
else draws a frame. 3 is the one to take if TUIkit apps tend to put tables
inside their own bordered panels.

### A30. Context menus on rows and on the selection — and does `onRowActivate` give way to `primaryAction`?

*`TableRowContent.contextMenu(menuItems:)`,
`TableRowContent.contextMenu(menuItems:preview:)`,
`View.contextMenu(forSelectionType:menu:primaryAction:)`*

SwiftUI gives a table's rows a context menu two ways. `.contextMenu` on a
row gives that row its own menu. `.contextMenu(forSelectionType:menu:primaryAction:)`
on the table (or a `List`) builds one menu from the set of rows it acts on: a
right-click on a selected row acts on the whole selection, on an unselected
row on that row alone, on empty space on none; `primaryAction` runs on a
double-click or Return with the same set.

TUIkit has `.onRowActivate(_:)` on `List` and `Table`, its own spelling of
`primaryAction` with one row's id where SwiftUI hands a set. A right-click on
a table row does nothing; a `.contextMenu` on a cell's view is dropped with
the cell's other mouse regions (B46).

Nothing shipped: the three modifiers do not compile.

**Options.**

1. **Both menus on `Table` and `List`, through one menu host resolved when
   it opens; `primaryAction` replaces `onRowActivate`.** The host is
   `ContextMenuModifier`'s presentation with its items chosen at the press —
   from the row under the pointer, or Shift+F10 on the cursor row — and the
   keyboard and dismissal it already has. `onRowActivate` goes, as every
   superseded TUIkit spelling has before 1.0: call sites in Example, Stress
   and the tests move to `primaryAction`, whose set is the selection, or the
   cursor row when nothing is selected. A day and a half.
2. **The same, keeping `onRowActivate`** as a TUI-specific modifier beside
   `primaryAction`. Two ways to say one thing, which the no-shims rule exists
   to prevent. Same price, less the migration.
3. **Row menus only.** `contextMenu(menuItems:)` on rows, through the same
   host; the selection menu and `primaryAction` stay open. A day.

**Recommendation:** 1. The selection menu is the macOS idiom for tables —
Finder's and Mail's lists work that way — and `primaryAction` is what
`onRowActivate` was standing in for.

### A31. Sections among a table's rows?

*`Section.TableRowValue`, `Section.TableRowBody` (`Section` as
`TableRowContent`), `TableHeaderRowContent` and its three members*

SwiftUI's rows can be grouped: `Section { rows } header: { Text("…") }` in a
`rows:` closure draws a header row — a view across the table's width —
above the section's rows.

TUIkit's table draws only rows that are values; every path through it — the
row window, the cursor, the selection, the row memo, the multi-line heights,
the mouse bands — counts rows by their index into the data. Nothing shipped:
`Section` in a `rows:` closure does not compile.

**Options.**

1. **Header rows.** A header is an entry of its own among the drawn bands —
   a line the full width of the row content, its view rendered there, never
   selected, stepped over by the cursor as a `.selectionDisabled()` row is —
   with the index arithmetic taught that some entries are not rows. A day,
   most of it the multi-line path and tests.
2. **Decline.** Tables that need groups use a hierarchical table, which
   ships.

**Recommendation:** 1. Grouped rows are common in macOS tables, and a
`List`'s sections already show what the header line should look like.

*Wave 11a's entries (A32–A33, B48–B51): every string was measured on SwiftUI, macOS 15, by rendering with `ImageRenderer` and reading the picture back with Vision; the probes are in the session notes, `w11a/probe`. A pass on macOS 26 is owed.*

### A32. `.textVariant(.sizeDependent)`: the narrower spellings of every live text

*`SizeDependentTextVariant`, `TextVariantPreference.sizeDependent`*

**Shipped:** `TextVariantPreference`, `FixedTextVariant`, `.fixed` and
`Text.textVariant(_:)`. Fixed is SwiftUI's default — always the widest
variant — and what every TUIkit text does, so `textVariant(.fixed)` returns
the text as it is. `.sizeDependent` is absent, so asking for it does not
compile.

It is not a no-op in SwiftUI. Measured on macOS 15 (one line, the width
falling in 6 pt steps), a size-dependent text chooses the widest of a ladder of
spellings that fits:

| Text | Ladder, widest first |
|---|---|
| `.offset(to:)` | `1 hour, 2 minutes` → `1 hr, 2 min` → `1h 2m` |
| `.reference(to:)`, relative | `2 minutes ago` → `2 min. ago` → `2m ago`; `in 1 hour` → `in 1 hr.` → `in 1h`; `yesterday` has none |
| `.reference(to:)`, absolute | `Friday, May 8` → `Fri, May 8` → `5/8`; `June 2025` → `Jun 2025` → `6/25`; with three fields `Friday, May 8 at 11 PM` → `Fri, May 8 at 11 PM` → `5/8, 11` |
| `.timer`, in units | `1 hour, 2 minutes` → `1 hr 2 min` → `1:02` |
| `.stopwatch` | `01:02:05.50` → `1:02:05` → `1:02` → `1h` |
| `Text(_:style: .relative)` | `1 hr, 2 min` → `1h 2m` |
| `Text(_:style: .offset)` | `+1 hour` → `+1 hr` → `+1h` |
| `Text(_:style: .date)` | `May 8, 2026` → `May 2026` → `2026` |
| `Text(_:style: .time)` | `11:13 PM` → `11 PM` |
| `Text(_:style: .timer)`, the timer on its face | none |

Without a line limit the widest always fits by wrapping, and nothing changes
(measured the same way).

**Options:**

1. **Build it.** Each live source offers its ladder (Foundation spells most
   rungs: `Duration.UnitsFormatStyle` and `Date.ComponentsFormatStyle` have
   abbreviated and narrow widths, `Date.FormatStyle` has abbreviated and
   numeric months, and the anchored relative style abbreviated units); a
   `.sizeDependent` text measures its rungs against the proposal and its line
   limit and draws the first that fits, the measure and the render choosing
   alike. About a day, most of it the per-rung measurements (German among
   them) and the tests. Only a text that asks pays: a measure per rung tried.
2. **Build the unit spellings only** (offset, relative, the timer's units):
   the abbreviated and narrow widths, half a day. The reference's absolute
   form and the date and time styles stay fixed — a quiet difference from
   SwiftUI for those, which the parity rules argue against.
3. **Leave it absent** (as now): ported code that asks for it does not
   compile.

**Recommendation:** 1, later — after the waves, since it touches every live
source and nothing else depends on it. 2 is the kind of partial honour the
parity rules warn about.

### A33. `\(accessibilityName: color)`: a colour's spoken name

*`LocalizedStringKey.StringInterpolation.appendInterpolation(accessibilityName:)`*

SwiftUI interpolates "a localized description of a color for accessibility".
Measured on macOS 15, in light mode: `.red` reads `dark red`, `.blue` and
`Color(red: 0.2, green: 0.4, blue: 0.8)` `dark blue`, `Color(white: 0.5)`
`dark gray`, `.primary` `black`, the accent colour `dark blue`. The names
come from Apple's accessibility colour naming, which is private and has no
counterpart in the open-source Foundation.

**Options:**

1. **A namer of TUIkit's own:** a colour's resolved RGB in OKLCH, bucketed to
   a dozen hue names with `dark`/`light`/`vivid` qualifiers, in the
   framework's seven languages. It would not say what SwiftUI says for every
   colour (`.red` is `dark red` there, which no simple rule predicts); a
   palette colour names its resolved value. Half a day with the
   translations.
2. **Decline** (a `notImplemented` entry): code that uses it does not
   compile, and the app says what it means in words.
3. **Interpolate the colour's own description** (`String(describing:)`):
   compiles, and reads `Color(…)` to a screen reader — the quiet wrong answer
   the parity rules forbid.

**Recommendation:** 2 now; 1 if a screen-reader user of a TUIkit app asks for
it. Shipped: nothing, so it does not compile.

*Wave 12's entries (A34–A40, B52–B61; its `Transaction.dismissBehavior` joined A22): SwiftUI's behaviour is from its doc comments unless an entry says it was measured; measurements are from probes built against the macOS 26.2 SDK and run on macOS 15, kept in the session notes, `w12/probe`.*

### A34. `BlurReplaceTransition`: a fade in place of the blur, or wait for W16?

*`BlurReplaceTransition` (and `Configuration`, `.downUp`, `.upUp`,
`init(configuration:)`, `configuration`, `body(content:phase:)`),
`Transition.blurReplace`, `Transition.blurReplace(_:)`*

SwiftUI documents it as "combining blurring and scaling effects": `.downUp`
scales the view down while removing it and up while inserting it, `.upUp`
scales up both ways. The scale half is TUIkit's `.scale` reveal. The blur half
is the per-pixel filter the map declines (`VisualEffect.blur*`, confirmed by
the Wave 17 review, P14), and Wave 16 owns blur as a whole.

**Options.**

1. **Leave it out until Wave 16 decides blur.** Free. Code using it fails to
   compile, which is the rule for anything not honoured.
2. **Ship it as a scale and a fade.** A blurred-out view reads, at a cell's
   resolution, as one that has faded: there is no sub-cell detail to soften,
   and the opacity compositor already dissolves a cell's colours toward what
   is behind it. `.downUp` becomes the reveal from the centre plus the fade;
   `.upUp` the same on insertion and a fade alone on removal (a reveal cannot
   grow past the slot). An hour with tests, and the doc comment says
   the blur is drawn as a fade.
3. **Option 2, plus a cell "blur"**: soften the glyphs on the way out (shade
   blocks `▓▒░`, or the dim attribute) as well as the colours. A day, and a
   drawing that has no precedent in TUIkit.

**Recommendation:** 2, if Wave 16 does not give blur a cell reading of its
own; 1 until then. Nothing ships.

### A35. Symbol effects: declare TUIkit's own `SymbolEffect` types?

*`View.symbolEffect(_:options:isActive:)`, `View.symbolEffect(_:options:value:)`,
`View.symbolEffectsRemoved(_:)`, `Transition.symbolEffect`,
`Transition.symbolEffect(_:options:)`, `ContentTransition.symbolEffect`,
`ContentTransition.symbolEffect(_:options:)`, `WiggleSymbolEffect.custom(angle:)`*

Every one of these takes a value from Apple's **Symbols** framework
(`SymbolEffect`, `IndefiniteSymbolEffect`, `DiscreteSymbolEffect`,
`TransitionSymbolEffect`, `SymbolEffectOptions`, `PulseSymbolEffect`, …), not
from SwiftUI. Symbols does not exist on Linux or Windows. The Wave 17 review
(P4) found the effects a single glyph can show — appear, disappear, replace
(cross-fade through the opacity compositor), pulse and breathe (an
`AnimatedCellRun` on the glyph's cell) — and the ones it cannot, which need
glyph geometry or layers: bounce, scale, wiggle, rotate, variable colour.

**Options.**

1. **Decline the family.** The modifiers fail to compile; an SF Symbol stays a
   still glyph.
2. **Declare TUIkit's own Symbols vocabulary** under Apple's names, for the
   five effects a glyph can show: the protocols, `SymbolEffectOptions`
   (`.repeating`, `.nonRepeating`, `.repeat(_:)`, `.speed(_:)`), and the
   effect structs with their builder members. Bounce, scale, wiggle, rotate
   and variable colour are left out, so asking for one fails to compile —
   which is also why `WiggleSymbolEffect.custom(angle:)` stays absent under
   either option. Two to three days with tests. It is the same policy question
   as A18 (declaring API that belongs to another Apple framework): a file that
   imports both TUIkit and Symbols would see two `PulseSymbolEffect`s.
3. **Option 2 with only the transition half** (`Transition.symbolEffect`,
   appear/disappear/replace), which is the part an ordinary port most often
   carries. About a day.

**Recommendation:** 2, after A18 is answered; until then 1.

### A36. `matchedGeometryEffect` waits on O4

*`View.matchedGeometryEffect(id:in:properties:anchor:isSource:)`*

`@Namespace` shipped in Wave 9, so the identifier half exists. The effect
itself — carrying a view from the source's frame to its own — and its
`MatchedGeometryProperties` are O4 of the refusal review, with options from
position-only (whole cells, size snaps) to a full re-layout per frame.
Nothing ships until O4 is answered.

### A37. `phaseAnimator(_:trigger:content:animation:)` waits on O2

*`View.phaseAnimator(_:trigger:content:animation:)`*

The animator views are O2 of the refusal review. If O2 goes (b), this is the
trigger form of that live phase animator, and its completion advance would use the
animation completions this wave adds.

### A38. `Animation.shouldMerge` and `Animation.velocity` wait on O3

*`Animation.shouldMerge(previous:value:time:context:)`,
`Animation.velocity(value:time:context:)`*

Both take an `AnimationContext`, which belongs to the `CustomAnimation`
family that O3 of the refusal review reopens. They are the merge and velocity
half of a custom animation's contract; with O3 (b) they would answer `false`
and the closed-form velocity respectively.

### A39. The geometric visual effects wait on Wave 16 (A27)

*`VisualEffect.rotationEffect(_:anchor:)`,
`VisualEffect.rotation3DEffect(_:axis:anchor:anchorZ:perspective:)`,
`VisualEffect.scaleEffect(_:anchor:)`, `VisualEffect.scaleEffect(x:y:anchor:)`,
`VisualEffect.transformEffect(_:)`*

The `View` modifiers of the same names are Wave 16's (sub-cell geometry, an
owner decision: A27). The visual-effect spellings are the same requests made from a
geometry proxy, and should be answered with them; `VisualEffect` itself and the
effects with a cell reading are this wave's.

### A40. Should a content change dissolve by default under an animation?

*`EnvironmentValues.contentTransition`'s default; the drawing of `Text` (and
`Image`) when what it shows changes inside `withAnimation`*

SwiftUI's environment holds an unnamed default content transition (measured:
equal to none of `.identity`, `.opacity`, `.interpolate`), under which a
`Text` whose string changes inside an animation cross-fades. TUIkit's default
draws the change at once, as it always has; `contentTransition(_:)` shipped
(B61) dissolves only where it is written.

**Options.**

1. **Keep the default instant.** Free. A port that relied on the default
   cross-fade snaps until it adds `.contentTransition(.opacity)`.
2. **Dissolve by default, in `Text` and `Image`.** Each keeps its last
   drawing and dissolves to a changed one under an animated transaction, as
   the modifier does for a subtree. The price is in the hottest view there
   is: every `Text` drawn under an animation compares its lines with the last
   frame's and, while a change dissolves, draws twice; and every `Text` keeps
   one drawing in state storage. A day, plus the A/B on `Stress` that a change
   to `Text` needs.

**Recommendation:** 1, until a port shows the default being relied on.

### A41. Materials wait on O5

*`ShapeStyle.ultraThinMaterial`, `.thinMaterial`, `.regularMaterial`,
`.thickMaterial`, `.ultraThickMaterial`, `ShapeStyle.materialActiveAppearance(_:)`,
`View.materialActiveAppearance(_:)`, `\.materialActiveAppearance`,
`\.backgroundMaterial`*

A material is a blurred, translucent surface. O5 of the refusal review asks
whether TUIkit's should be a translucent palette surface composited over what
is behind, its thickness an alpha and with no blur (recommended), or stay the
`dimmed()`/`overlayBackground` substitution. These symbols ship or are
declined with that answer.

### A42. Rich-text editing waits on P8

*`AttributedTextSelection` and its members, `AttributedTextValueConstraint`,
`AttributedString.replaceSelection(_:with:)` and `(_:withCharacters:)`,
`AttributedString.subscript(_:)` (by selection),
`AttributedString.transform(updating:body:)`,
`AttributedString.transformAttributes(in:body:)`,
`AttributedString.init(transferable:in:)`,
`View.attributedTextFormattingDefinition(_:)`*

SwiftUI's rich-text editing: a `TextEditor` over an `AttributedString`, its
selection carrying typing attributes, and constraints on which attributes an
edit may set. All of it presupposes `Text(AttributedString)`, which P8 of the
refusal review recommends implementing (bold, italic, underline,
strikethrough and colours map to cells). After P8, an attributed editor is
the plain editor with styled runs, about two days; the selection type itself
is a day on top of `TextSelection`, which has shipped.

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

### B7. Key-press phases: every press is `.down`, and there is no `.up`

*`KeyPress.Phases.down`, `.repeat`, `.up`, `.all`; `KeyPress.phase`*

SwiftUI tells three phases apart: the press, each auto-repeat of a held key,
and the release. Measured on macOS 15, a `phases: .up` handler hears only the
release, and the default `[.down, .repeat]` hears the press and its repeats.

A terminal in its legacy encoding reports none of that. A held key's repeats
arrive as more copies of the same bytes, and a release sends nothing at all.

**Shipped:**

- `.down`, `.repeat` and `.all` exist, with SwiftUI's raw values (1, 2,
  `Int.max`).
- Every press is reported as `.down`.
- A handler whose phases include `.down` or `.repeat` hears every press. So
  the default, and an explicit `[.down, .repeat]`, mean exactly what they mean
  in SwiftUI. A `.down`-only handler also hears the repeats, and a
  `.repeat`-only one also hears the first press. Both over-fire visibly; neither
  drops anything silently.
- `.up` is absent, so `onKeyPress(phases: .up)` and `press.phase == .up` fail
  to compile. A release handler could never run.

**The fuller version** is the kitty keyboard protocol, which reports press,
repeat and release explicitly on the terminals that speak it. It is priced in
A4, together with the open question of whether `.up` should then compile
on terminals that will never fire it.

### B8. `KeyboardShortcut.Localization` is recorded, and every strategy behaves as `.custom`

*`KeyboardShortcut.Localization` (`.automatic`, `.withoutMirroring`,
`.custom`), `KeyboardShortcut.localization`,
`KeyboardShortcut.init(_:modifiers:localization:)`,
`View.keyboardShortcut(_:modifiers:localization:)`*

On macOS, `.automatic` (the default) does two things.

- It remaps a shortcut whose character is awkward on the user's layout. `⌘[`
  needs ⌥5 on a German keyboard, so it becomes `⌘Ö`.
- It mirrors a directional shortcut under a right-to-left layout.

`.withoutMirroring` remaps but does not mirror, and `.custom` does neither.

**Shipped:** the type, the three values, the stored property (compared, so
`KeyboardShortcut("a", localization: .custom) != KeyboardShortcut("a")` as on
macOS), the initializer and the modifier. All three behave as `.custom`.

That is honest on its own, because neither half has anything to act on:

- A terminal reports the character a key typed, never the key's place on
  the keyboard. A shortcut already matches its character however the
  layout types it, and there is no US-layout position to remap from.
- TUIkit lays out left to right only (B1 in the main decisions doc), so
  there is nothing to mirror.

**The fuller version:**

- *Mirroring* comes free with right-to-left layout, if B1 is ever taken up.
  Mirror `[`/`]` and `{`/`}` under `.automatic` and leave them under the
  other two.
- *Remapping* would need the key's position. The kitty keyboard protocol's
  "report alternate keys" enhancement sends the base-layout key alongside
  the character, so it is the same negotiation A4 prices, plus a
  remapping table. That table is AppKit's, and it is not public, so it would
  have to be inferred per layout. I would not do it: an app that wants
  layout-aware shortcuts in a terminal is better served by bare keys.

### B9. Copy, cut and paste commands carry text, and exist only where `NSItemProvider` does

*`View.onCopyCommand(perform:)`, `View.onCutCommand(perform:)`,
`View.onPasteCommand(of:perform:)`, `View.onPasteCommand(of:validator:perform:)`*

**Shipped:**

- On Apple platforms, all four, on the focus path's command stage.
- The keys are SwiftUI's ⌘C, ⌘X and ⌘V resolved through `\.commandKey`
  (Control by default). A paste is also the terminal's own bracketed paste.
- A copy or cut writes the text of every item that loads as a string, one
  per line. A paste offers one item, the clipboard's text, and triggers only
  for a type that accepts text.

The terminal's clipboard holds one string, so what does not read as text (an
image, a file promise) is not written. That is the medium, not a stub: the
action still runs, and a cut still deletes.

**Absent on Linux**, because swift-corelibs-foundation has no `NSItemProvider`
and there is no `UniformTypeIdentifiers`. Gated
`#if canImport(UniformTypeIdentifiers)`, so the same source fails to compile
there rather than compiling to nothing.

**The fuller version** would be a TUIkit-specific spelling that takes and
returns `String`s and works on every platform: `onCopyCommand(text:)`, say.
That is an addition, not a fix, so I have not made it. Say if you want it.

### B10. Item-provider drag and drop stays in the app, and only cancel and forbidden change a drop

*`View.onDrag(_:)`, `View.onDrag(_:preview:)`, `View.itemProvider(_:)`, `View.onDrop(of:isTargeted:perform:)`,
`View.onDrop(of:delegate:)`, `DropDelegate`, `DropInfo.hasItemsConforming(to:)`,
`DropInfo.itemProviders(for:)`, `DropOperation` (+ `.Set`), `DropProposal`*

**Shipped:**

- On Apple platforms, the four modifiers and the delegate, riding TUIkit's
  in-app drag session. An `onDrag` provider, or a `draggable` string or URL
  wrapped as SwiftUI wraps a `Transferable`, lands in an `onDrop` whose types
  it conforms to.
- The delegate is called in SwiftUI's order: validate once, enter, update on
  each move, then exit or perform.
- `DropOperation`, its `Set` and `DropProposal` are values everywhere.

Two things SwiftUI's drop does are not here:

- *The operation's meaning.* A proposal of `.cancel` or `.forbidden` refuses
  the drop, and the drag goes home. `.copy`, `.move`, `.delete` and `.alias`
  all accept it. On macOS they differ in the pointer's badge and in what the
  source application is told. A TUIkit drag has no badge and never leaves the
  app, so the delegate's `performDrop` is where any difference has to be
  made.
- *`operationOutsideApplication`.* It is recorded and never applies.

`DropOperation.Set`'s raw values are TUIkit's own: SwiftUI does not document
its own, and it is macOS 26 only, so it could not be probed on this machine.

**The fuller version:** a badge beside the drag preview naming the proposed
operation (`+` for copy, as Finder draws), and a source-side callback when a
drop completes with `.move` or `.delete`. SwiftUI's is `onDragSessionUpdated`,
which the `DragSession*` family rule declines. About half a day for the
badge; the callback belongs with that family's re-examination in Wave 17.

### B11. `Menu(primaryAction:)` draws as two adjoining buttons

*`Menu.init(content:label:primaryAction:)`, `Menu.init(_:content:primaryAction:)`
(key and string), `Menu.init(_:systemImage:content:primaryAction:)`*

SwiftUI's contract is one line: "the action to perform on primary
interaction with the menu". macOS draws it as a pull-down button whose body
runs the action and whose chevron opens the menu. TUIkit's earlier refusal
named that rendering, not the contract, and both of its stated blockers turned
out to exist in the package (a 2026-08 audit, finding 102).

**Shipped:** the label performs the action — Return, Space or a click — and
the menu opens from the caret beside it by a click, or from the label by the
Down arrow. The caret takes clicks and no focus, so the control is one Tab
stop. Under `.menuIndicator(.hidden)` the caret goes and the arrow remains.
Drawn as the label's button and the caret's, side by side:
`▐ Export ▌▐ ▾ ▌`, against the plain menu's `▐ Export ▾ ▌`.

**The fuller version** is one control face split by a rule —
`▐ Export │ ▾ ▌` — which needs the button style's caps to frame two hit
regions in one body; and a press-and-hold on the label to open the menu, as
macOS does, now that Wave 7's long press exists. Half a day together. The
status bar's hint for the label says "press" today; it could add "↓ menu".

### B12. `buttonRepeatBehavior(.disabled)` cannot stop a held key repeating

*`ButtonRepeatBehavior` (`.automatic`, `.enabled`, `.disabled`),
`EnvironmentValues.buttonRepeatBehavior`, `View.buttonRepeatBehavior(_:)`*

SwiftUI names three ways to hold a button: the mouse, its keyboard shortcut,
and Space while it is focused. Under `.enabled` each repeats the action;
otherwise each acts once.

**Shipped:** the mouse half exactly — under `.enabled` the press acts at once
and repeats at the auto-repeat cadence a `Stepper`'s arrows use until the
release; otherwise the button acts once, on the release, as before.

**What it cannot do:** a held key repeats under every setting. The terminal
resends a held key at its own autorepeat rate and reports no release, and each
arrival is a press, so a held Return or Space — or a held shortcut — acts again
and again even under `.disabled`. Telling a repeat from a fresh press needs
the kitty keyboard protocol's repeat and release events (A4); with A4, this
becomes exact.

### B13. A segmented picker's segments are each a focus stop

*`SegmentedPickerStyle` / `.segmented`, `PalettePickerStyle` / `.palette`,
`PaletteSelectionEffect`, `View.paletteSelectionEffect(_:)`*

**Shipped:** the options side by side as touching bordered buttons, the
selected one bordered-prominent — `ControlGroup`'s strip, and the look a
group of buttons already has here. Tab walks the segments and Return, Space or
a click picks one. A palette lays out the same way, its marking set by the
selection effect.

**What differs:** a macOS segmented control is one focus stop whose segments
the arrow keys walk. Here each segment is a stop, so Tab takes as many presses
to cross a segmented picker as it has options.

**The fuller version** draws the strip as one control — `▐ S │ M │ L ▌` on
one face, the selected segment in the accent — and keys it as the horizontal
radio group already is: one stop, Left and Right moving within it, Return
choosing (or choosing as the arrows move, as macOS does for a single-choice
segmented control). The radio group's handler is that model already; the
work is the drawing, about half a day.

### B14. `.stepperField` draws no arrows, and `.compact` opens no popover

*`StepperFieldDatePickerStyle` / `.stepperField`, `CompactDatePickerStyle` /
`.compact`*

TUIkit's date picker is an editable field: Left and Right choose a component,
Up and Down step it, and the wheel steps the component under the pointer.

**Shipped:** both styles draw that field. A stepper field's job — stepping the
selected component — the field does by key and by wheel, but it draws no
arrows beside itself to click; and a compact picker's text is the field's,
but clicking it opens no calendar.

**The fuller version:** a `▲▼` pair after a stepper field, each a click
target stepping the selected component (S, half a day with tests); and a
compact field that opens the graphical calendar (`.graphical`, which has
shipped) in a popover; small now that the calendar exists.

### B15. A `ForEach` row of several views is one subview, not several

*`Group(subviews:transform:)`, `ForEach(subviews:content:)`,
`SubviewsCollection`, `LayoutSubviews`, `SectionCollection`*

SwiftUI takes a multi-view row apart: `ForEach(0..<2) { _ in Group { a; b } }`
is four subviews, and so is the same row as a `TupleView`. It does not take
`AnyView(Group { a; b })` apart: that is one subview per `AnyView`.

TUIkit resolves one child per element everywhere — stacks, `List`, `Table`,
layouts — and the subview APIs inherit that, so the loop above is two
subviews here, and `HStack { ForEach(…) { Group { a; b } } }` stacks each pair
vertically inside the row. A row of one view, which is nearly every row, is
exact.

**The fuller version** flattens a row that is itself a provider of several
views. That changes `ForEach.makeChild` (one element → several children), the
lazy child collection (its count is no longer the data's count, so a lazy
stack's window over a million rows needs an index from element to first
child), the row memo (keyed per element today) and the identity keys (a
row's children need a step under the element's key). It is a resolver change
for every container, not a subviews change, and it needs an A/B on `fanout`,
`megalist` and `table`, the scenarios whose frames are mostly row
resolution. Two to three days with the measurement.

### B16. A `Section` is taken apart only by the subview and section APIs

*`Section`, `Group(subviews:transform:)`, `Group(sections:transform:)`*

SwiftUI flattens a `Section` in a stack into its header, content and footer,
as the subview counts show (a section of two views with a header and a footer
is four subviews). TUIkit's `Section` in a stack still draws as one unit, with
the dimmed, bold header styling it has in a `List`.

The subview and section APIs take sections apart as SwiftUI counts them, and
hand the parts over as written — no header styling — because there the
custom container decides how a header looks.

**The fuller version** makes `Section` a provider of its parts in every
container that is not a `List`, `Form` or `Table`. That moves the drawing of
every page with a sectioned stack, so it is its own commit with the Stress
self-check, and it needs a decision on whether a header outside a list keeps
any styling. Half a day.

### B17. A subview proxy does not pass on a spacer flag or an alignment guide

*`Subview`*

`Subview` is a view that draws its member. A container laying out
`ForEach(subviews: content) { $0 }` sees the proxy, which says nothing about
being a `Spacer` or carrying an `.alignmentGuide` — those are static
properties of the member's type, and the proxy is one type for every member.
A stack therefore gives a proxied `Spacer` the share a flexible view gets,
which is close to but not the same as a spacer's.

Placing the collection or a slice (`HStack { subviews }`) hands the members
to the container directly, flags and guides intact, and that is the shape
SwiftUI's own examples use. The fuller version reads the flags off the
member at run time wherever a container meets a `Subview`; it is a cast per
child on the stack path, so it would be gated behind a stored flag. Half a
day.

### B18. `SectionConfiguration.actions` is always empty

*`SectionConfiguration.actions`, `SectionConfiguration.Actions`*

Nothing in TUIkit can attach an action to a section yet: SwiftUI's
`sectionActions(content:)` is a gap with its natural home in Wave 8, where
`List` draws actions in section headers. So every section's actions are an
empty view, which is the truth. When `sectionActions` lands, `actions` must
start returning what it set.

### B19. A guide does not travel out of a view type of the app's own

*`View.alignmentGuide(_:computeValue:)`, `Layout.explicitAlignment(of:in:proposal:subviews:cache:)`*

SwiftUI resolves a guide recursively through everything between it and the
container aligning on it. TUIkit now does the same through `VStack`,
`HStack`, `ZStack`, `.padding` (each moving the guide by where it put its
content) and a custom `Layout` (`explicitAlignment`), which closes the gap the
compatibility notes recorded: `.alignmentGuide(.decimalPoint)` on a `Text`
inside each row of a column aligns the rows on the point.

It stops at a view type of the app's own: a guide inside
`struct Row: View`'s `body` does not travel out of `Row`. A container decides
whether to ask a child about guides from a static witness
(`View._providesAlignmentGuide`), which the framework's containers now
forward from their content; an app's view states none, so it is not asked. It
also stops at any modifier that does not translate guides (`.border()`,
`.frame`, `.offset`): there a wrong position is the alternative.

**The fuller version** makes every composite view forward its `body`'s
witness by default (`Body._providesAlignmentGuide`, `false` for a `Never`
body), so the question reaches into every body type. The cost is where the
witness is read: `ChildView` construction, per child per walk, would recurse
through the child's whole static body type, not only the framework containers
in it. That is O(static subtree) per construction, which the per-pass measure
memo keeps to roughly O(nodes × depth) witness calls a frame — small on paper,
and exactly the kind of thing that has measured as a percent on `fanout` and
`deep` before. Half a day, plus an A/B on `deep`, `kitchensink`, `megalist`
and `table` on a quiet machine before it ships.

**A/B owed for what did ship.** The witness now forwards through `TupleView`,
`Group`, `ForEach`, `ConditionalView`, `Optional`, the three eager stacks and
padding, so constructing a `ChildView` for a container child ORs its
framework subtree's witnesses instead of reading one constant. A tree with no
guide still pays one stored `Bool` per child at layout time, as before; the
added cost is in the construction, and it was not measured (no benchmarks on
a shared machine). `deep` and `kitchensink`, the structure-heavy scenarios,
are the ones to A/B. One more: an app's own `Layout` cannot be known not to
override `explicitAlignment`, so inside a stack it is laid out once more per
walk to answer the stack's guide question (the framework's layouts state
`_definesExplicitAlignment = false` and are asked only when a subview may
hold a guide). Stress's `customlayout` scenario is the one to A/B for that.

### B20. A stack's `spacing: nil` is the default preference, not each pair's

*`HStack.init(alignment:spacing:content:)`, `VStack`, `LazyHStack`, `LazyVStack`,
`HStackLayout`, `VStackLayout`, `ViewSpacing`, `Layout.spacing(subviews:cache:)`*

The stacks now take SwiftUI's `spacing: Int? = nil` (it was `Int = 1` and
`Int = 0`), so `HStack(spacing: nil)` compiles. In SwiftUI, `nil` means "for
each pair of neighbours, the distance their `ViewSpacing`s ask for". Here
`nil` resolves, at `init`, to the distance two views of default preference ask
for — one column in a row, none in a column — and is used between every pair.

The two readings differ less than they sound. `ViewSpacing` has SwiftUI's
surface only: `init()` (one column beside, no row above or below), `.zero`,
and unions, which take per-edge maxima. So every preference a TUIkit view can
state is the default or less, edge by edge, and every vertical edge is 0.
Each pair's distance in a column is therefore always 0 — exact — and in a row
it is 1 unless BOTH neighbours are custom layouts whose
`spacing(subviews:cache:)` asks for no space on the facing edges. That pair
gets a column here and none in SwiftUI. A custom layout that spaces its
subviews by `LayoutSubview.spacing` does get the per-pair answer.

**The fuller version** resolves `nil` per pair inside the stacks: a stored
flag on `ChildView` saying the child can state a preference (it fits the
struct's tail padding), and per-gap spacings through
`distributeLinearSpace`, `totalLinearSpacing`, the assembly in both cores, the
lazy windows and the guide placement. That is a structural change to the
hottest layout path for a case that needs two zero-spacing custom layouts side
by side. A day, and the plan's rule applies: an A/B on `deep`, `kitchensink`,
`megalist` and `table` on a quiet machine before it lands. What shipped
changes nothing on the stack path — `nil` becomes the old constant at `init` —
so no A/B is owed for it.

### B21. `GridRow` outside a grid is its cells, not an `HStack`

*`GridRow`*

`GridRow`'s body was `HStack(alignment: alignment ?? .center, spacing: 1)
{ content }`, on the stated belief that SwiftUI degrades a row outside a grid
to a horizontal arrangement. The W05 probe refutes it: in SwiftUI
`VStack { GridRow { a; b } }` is pixel-identical to `VStack { a; b }` and
different from `HStack { a; b }`, and a custom `Layout` over two rows of two
sees four subviews. So this is a parity fix, not the reversal of a deliberate
deviation — but it moves pixels, so it is listed.

A row now hands its cells to the container around it, as a `Group` hands its
members, each marked so a grid still knows where one row ends and the next
begins. What changes for an app:

- A `GridRow` in a stack or a custom layout contributes its cells, not one
  row-shaped child. A `GridRow` drawn on its own stacks its cells vertically,
  as any run of views does.
- A `ForEach` of rows inside a `Grid` lines its cells up in the grid's
  columns whatever its elements. Before, a looped row whose element is
  `Equatable` reached the grid inside `ForEach`'s row memo, which the grid's
  row test did not look through, so the row spanned the grid as one cell; and
  a looped row's cells were resolved under the grid's identity rather than
  the row's, so two rows' cells could share a `@State` box. Both read from the
  code; the first is now pinned by a test.
- A row with no cells at all (`GridRow { if false { … } }`) is no row.
  `GridRow { EmptyView() }` is still a row one line tall: an `EmptyView` is a
  child here.

**Residual:** a `ForEach` of rows is taken apart only by containers that lay
cells out — `Grid`, `GridLayout`, and the stack layouts `AnyLayout` switches
it with. In a `VStack`, an `HStack` or an app's own layout each looped row is
still one child (B15's multi-view row), drawn as its cells stacked
vertically.

### B22. The content levels, and the two- and three-style `foregroundStyle`

*`HierarchicalShapeStyle`, `HierarchicalShapeStyleModifier`,
`View.foregroundStyle(_:_:)`, `View.foregroundStyle(_:_:_:)`*

The compatibility doc declined all four on two grounds. Neither held up:

- **Ambiguity.** A `.secondary` on `ShapeStyle` beside `Color.secondary` does
  not make `.foregroundStyle(.secondary)` ambiguous, because the `Color`
  overload is the disfavoured one. That is how SwiftUI is built too.
- **"A glyph has one layer."** True for a symbol, but the second and third
  styles are also what `.secondary` and `.tertiary` resolve to below the
  modifier, and a terminal honours that fully.

**What shipped.** With no foreground style above, the levels are the palette's
tiers, so `.foregroundStyle(.secondary)` paints what `Color.secondary` did.
`.quinary` is the quaternary tier at half strength. Under a `foregroundStyle`,
the levels are that style at macOS's label alphas (1, 0.5, 0.26, 0.1, 0.05),
composited at the cell. The two- and three-style forms name the second and
third levels outright; the levels past a named one are it faded by the same
ratios. A single-style `foregroundStyle` below clears the named levels, so
`.secondary` derives from the nearer primary.

**What moves for an app.** One case changes:
`.foregroundStyle(.secondary)` on a non-`Text` view, below an explicit
`foregroundStyle`. That is now the outer style at half strength, where it was
the palette's secondary tier, which is SwiftUI's behaviour.
`Text("a").foregroundStyle(.secondary)` is unchanged, because it still takes
`Text`'s `Color` overload (§3's remaining refusal).

**Enhancements to consider:**

- The 0.5 / 0.26 / 0.1 / 0.05 strengths are macOS's light-appearance label
  alphas. At 0.1 and 0.05 a faded glyph's colour is nearly the surface's, which
  the rendered contrast floor may lift. That is fine for a tint, but it is
  worth a live look in the 16- and 256-colour modes.
- A fuller version would carry the levels per palette (a palette naming its
  own faded tiers for an arbitrary foreground). That is a palette-protocol
  change, so I left it for you.


### B23. `ScrollPosition`: the request and the row are read separately, and `viewID` answers sooner than SwiftUI's

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

### B24. Content margins: where TUIkit applies them, and what a scroll indicator's margin moves

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
moves in with their rows. The fuller version is B6's real safe area.

### B26. `ScrollGeometry`: the visible area excludes the bars, and a vertical view's content is as wide as it is shown

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

### B27. Scroll phases: `.interacting` until a quarter of a second of quiet, and no velocity

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

### B28. `scrollIndicatorsFlash` returns the view: the indicators are already showing

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

### B29. `scrollTargetLayout()` returns the view

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

### B30. The `Transaction` scroll members: what "no adjustment" suspends

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

### B31. Bounce behaviour gates the overscroll allowance

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
idle (B27 gives the moment). Half a day, and it changes the default feel
of every scrollable, so it is yours to want.

### B32. `buttonSizing(.flexible)` widens a button's face; a plain button keeps its width

*`ButtonSizing` (`.automatic`, `.fitted`, `.flexible`), `View.buttonSizing(_:)`,
`EnvironmentValues.buttonSizing`*

A macOS 26 API, so SwiftUI's behaviour could not be measured on this
machine's macOS 15. What shipped follows its documentation: a flexible button
fills its primary axis. A button with a face (the bordered and prominent
styles and the other built-ins with caps) widens the face to the width it is
offered and centres its label; measured, it reports the offered width, flexible.
`.fitted` and `.automatic` fit the label, which is what every button did before.

**The open question** is plain, borderless and link buttons. They have no face,
so widening one changes only its hit area, invisibly. I left them at their
own width. SwiftUI's documentation says only that "certain styles" adapt. If a
macOS 26 measurement shows `.plain` widening, the change is the same
centring in `renderPlainStringLabel`, about an hour.

`Picker`, `ControlGroup` and `Toggle`'s button style, which the documentation
also names, do not read it yet. Each is a frame of its own, an hour apiece
once wanted.

### B33. Slider ticks, neutral value, enabled bounds and thumb visibility, read from the documentation

*`SliderTick`, `SliderTickBuilder`, `SliderTickContent`,
`SliderTickContentForEach`, `TupleSliderTickContent`, the three `Slider`
initialisers with `neutralValue:`/`enabledBounds:`/`ticks:`/`tick:`,
`View.sliderThumbVisibility(_:)`*

All macOS 26, so none of it was measured; what shipped follows SwiftUI's
documentation, and each reading below is a guess at the look:

- **Ticks:** a `╵` on the row under the track at each tick's value, at the
  column the knob takes for that value. Labels go on the row under that,
  centred on their marks; a label that would touch the one before it is left
  out rather than overlap. The rows exist only when there are ticks (or
  labels), and the row's other contents stay on the track's row.
- **`neutralValue:`:** the fill runs from the neutral value to the knob, on
  whichever side. For the knob and dot styles this is exact. For the fill
  styles (`.block`, `.bar`, the custom ones), the track is put together from
  whole cells of renders at the neutral value and at the value, so the edge at
  the neutral value is a whole cell. A neutral value draws the track as cells,
  never as a picture.
- **`enabledBounds:`:** every input stops at the bounds, and a value the app
  writes outside them is brought inside, as `bounds` already does. The track
  beyond them is drawn in a disabled slider's colours.
- **`currentValueLabel:`:** SwiftUI says not every style shows it. TUIkit's
  slider draws a numeric read-out, so a label given here replaces it.
- **`sliderThumbVisibility(.hidden)`:** the knob's cell shows the fill's end.
  On the `.marker` track, which has no fill, nothing then shows the value.

**Fuller versions:** sub-cell edges at the neutral value for the fill styles
(the ramps only grow rightward, so a leftward edge needs mirrored glyphs most
fonts lack); and a measured look once a macOS 26 machine is available.

### B34. A focused-value reader drawn ahead of its publisher catches up a frame later

*`FocusedValue`, `FocusedBinding`, `View.focusedValue(_:_:)`,
`View.focusedSceneValue(_:_:)`*

SwiftUI's readers are mostly `Commands` and toolbar items, which are updated
outside the view graph. A terminal has neither, so TUIkit's readers are views,
and they usually sit beside the publisher — a detail pane next to a list, a
status line above it — and are drawn before it in the same walk.

**Shipped:** a read answers from this frame's publications where the publisher
has already posted, and from last frame's where it has not. Every table handed
to a reader during a render is kept, and the reading is repeated at the end of
the pass against the frame's final publications and focus; if it differs, the
run loop is asked for one more frame. So a reader shows a value that changed
this frame one frame late (about 17 ms at the default rate), and a value that
did not change at once. A value that cannot be compared — a closure, a
`Binding` — counts as unchanged while the same view publishes it, so a closure
rebuilt every render cannot keep the loop spinning; a `Binding` reads through
to its source wherever it is read, so it is never stale either.

Two smaller readings, both SwiftUI-silent:

- Of several scene values for one key with none on the focus's path, the
  first published in the tree wins.
- A reader on the page beneath a sheet (the dimmed backdrop) reads the live
  tree's publications; the backdrop's own publishers publish nothing, since
  they are a picture of the page.

**The fuller version** removes the late frame: a publisher-only walk before the
real one, or deferring the readers' subtrees to the end of the walk. The first
is a second walk of every page that uses the API (a measure-shaped walk that
renders nothing, which the memos would mostly serve); the second breaks the
one-pass layout. Neither seems worth it for a one-frame delay that only a
reader ahead of a changing publisher sees. **A/B owed:** a reader records an
unkeyed read, so every memo above it declines to store; on a page whose root
holds a reader that is the whole page. Publishers are replayed by the memo, so
they cost nothing on a served frame.

### B35. What "when no other view has focus" means for a preferred default

*`View.prefersDefaultFocus(_:in:)`, `View.focusScope(_:)`, `ResetFocusAction`,
`EnvironmentValues.resetFocus`*

SwiftUI's documentation says the preference "sets the initial focus preference
when no other view has focus", is "limited to the focusable ancestor that
matches the provided namespace", and that a reset reevaluates default focus
"when the currently-focused item is within the provided namespace". Its
examples are tvOS ones. Three readings were needed:

- **Who has focus.** TUIkit focuses the first control of a screen or a newly
  presented sheet by itself, mid-render. That choice is not counted as a view
  having the focus, so the preferred control takes it from there; a focus the
  user, an app's `@FocusState` write or a `.defaultFocus` put somewhere is
  left alone. While an unapplied scope or preference is on screen the
  automatic choice waits for the end of the pass, so the first control inside
  a scope does not flicker through the focus; one before the scope can (it has
  registered before the scope was seen).
- **Once.** The initial preference is applied on the frame it first appears,
  then spent until its scope leaves the screen — the rule `.defaultFocus`'s
  `.automatic` priority already follows here.
- **No scope.** A preference whose namespace has no `.focusScope` applies to
  the whole screen, and a reset in that namespace moves the focus from
  anywhere.

**The alternative readings** are each a line to change: count the automatic
choice as holding the focus (then a preference only ever acts on a reset), or
make a scope-less preference inert. Neither has an obvious use. Not probed on
a SwiftUI build: focus needs a key window, which an offscreen hosting view does
not have.

### B36. Preventing termination stops the quit key, and "automatic" prevents nothing

*`View.presentationPreventsAppTermination(_:)`,
`View.dialogPreventsAppTermination(_:)`*

**Shipped:** `true` stops the quit key (`q` by default, or the app's
`quitShortcut`) and takes it off the status bar while the presentation is
drawn; `false` and `nil` leave it working. Several statements combine as
SwiftUI documents for the sheet form: a non-`nil` one overrides `nil`, and
`true` takes precedence over `false`. Signals are not stopped — Ctrl-C and
`kill` still end the app, which is what a force quit is on macOS and the only
way out of a terminal app that has stopped listening.

**What differs:** SwiftUI's `nil` is an automatic rule that usually prevents.
A sheet prevents unless its toolbar holds a single confirmation or
cancellation item; a dialog prevents unless it has one non-destructive button,
is not critical and holds no text field. TUIkit's `nil` keeps what it did
before this wave: the quit key works behind every presentation, as the
escape hatch its status bar offers.

**The fuller version** adopts macOS's automatic rule. The dialog half is a
few lines — the button roles are known (`alertActionButtons`), severity has
shipped, and alerts take no text fields yet. The sheet half has nothing to
read: a terminal sheet has no toolbar, so the rule would collapse to "a sheet
always prevents", which would take the quit key away behind every sheet in
every app. That is the decision: I would adopt the dialog rule and leave
sheets at "never".

### B37. A dismissal confirmation asks before the reader's ways out, not before `dismiss()`

*`View.dismissalConfirmationDialog(_:shouldPresent:actions:)`,
`View.dismissalConfirmationDialog(_:shouldPresent:actions:message:)`*

SwiftUI's doc says the dialog is presented "when a dismiss action has been
triggered", and on macOS "when attempting to dismiss the window for this
view".

**Shipped:** on a presentation's content, the presentation's own ways out ask
first — Escape, an outside click (a popover), the status-bar item; on an
app's top-level content, the quit key does, the terminal's nearest thing to
closing the window. Cancel keeps what was about to go; every other action runs
and then lets it go.

**What is not intercepted:** an app's own `@Environment(\.dismiss)` call. It
is a decision the app made in code, and its usual shape — a Save button that
saves and dismisses — would otherwise ask about the changes it has just saved
whenever `shouldPresent` lags a frame. Nor is a pushed `NavigationStack`
screen's Escape (back), or a signal.

**The fuller version** wraps `\.dismiss` for the content too. The catch is
cost, not code: `DismissAction` is not `Equatable`, so writing one into the
environment turns the memos off below it, and on a top-level content that is
the whole app. It wants `DismissAction` made comparable first (an
identity-compared box, as `searchable`'s dismissal is), which every presenter
writing one would gain from — half a day with the memo tests.

### B38. Search scopes show while the search is under way, by a terminal's reading of "presented" and "cancelled"

*`View.searchScopes(_:scopes:)`, `View.searchScopes(_:activation:_:)`,
`SearchScopeActivation`*

SwiftUI shows the scope bar "when SwiftUI presents search" (macOS) or "when
someone enters text" (iOS), and hides it "when someone cancels the search".
On macOS the search field lives in a toolbar and is presented by clicking it.
Here it is always on screen at the top of the searchable subtree.

**Shipped:** presented is the field holding the focus, as `isSearching` already
was; cancelled is `dismissSearch` (or `isPresented = false`), or leaving the
field with nothing typed. So under `.onSearchPresentation` and `.automatic`
(macOS's default) the scopes show while the field has the focus or the query
is not empty; under `.onTextEntry`, while the query is not empty. Under both
they stay while the focus is in them, or Tab from the field would hide the
picker it was heading for.

**The alternative** is to show the scopes whenever the field is on screen,
since a terminal's field is never hidden. That reads well for a dedicated
search page but makes `.onTextEntry` meaningless, so it would have to be a
TUIkit-only activation rather than a reading of SwiftUI's.

### B39. Suggested search tokens are a row of buttons, not entries in the suggestions menu

*`View.searchable(text:tokens:suggestedTokens:placement:prompt:token:)`,
`View.searchable(text:tokens:suggestedTokens:isPresented:placement:prompt:token:)`*

SwiftUI lists suggested tokens in the search field's suggestions, as it lists
`searchSuggestions`. TUIkit's suggestions are a drop-down of text completions
(`TextSuggestions`), opened by Down at the caret; an entry fills the field
with its text and has no notion of becoming a token.

**Shipped:** the suggested tokens are a row of buttons under the field, shown
while the field holds the focus with nothing typed (and while the focus is in
the row), on the same terms as the scopes; choosing one appends it to `tokens`,
and a token already chosen is not offered again. The tokens themselves draw in
the field as `[Apple] [Pear]`, in the accent colour, and Backspace in an empty
field removes the last.

**The fuller version** teaches the suggestions drop-down a second kind of entry,
one that appends a token instead of completing text, and offers the suggested
tokens there, above any `searchSuggestions`: the menu, its keyboard handling
and its Return-to-submit rule all live in one place (`TextInputSuggestions`),
so it is about half a day with tests.

### B40. An inspector is a split view's trailing pane: always a column, and its width bounds are not enforced

*`View.inspector(isPresented:content:)`, `View.inspectorColumnWidth(_:)`,
`View.inspectorColumnWidth(min:ideal:max:)`*

**Shipped:** the inspector is the trailing pane of an `HSplitView` beside the
view — macOS's presentation in a regular size class — starting at the width
named on its content (in columns) or 30, with the split's divider: a focus
stop the arrow keys move and the pointer drags. The view keeps its identity and
state while the inspector comes and goes.

**What differs:**

- A compact horizontal size class does not turn the inspector into a sheet,
  as iOS does. Here the size class is only compact when an app sets it, and
  nothing TUIkit draws reads it yet (B3).
- `min` and `max` are accepted and not enforced: the divider moves the column
  from one cell to all but one. SwiftUI documents that a platform may use a
  different width than asked, so this is within the contract, but it is the
  weaker reading.
- There is no keyboard command to show or hide the inspector — SwiftUI's comes
  from `InspectorCommands`, and `Commands` are O13.

**The fuller version** gives `HSplitView`'s panes bounds — a per-pane minimum
and maximum the divider stops at, which a `.frame(minWidth:maxWidth:)` on a
pane could state for every split, not only inspectors — about half a day; and
the sheet adaptation follows whatever B3 decides about compact size classes.

### B41. Three drawings chosen without a measurement: critical severity, the dialog icon, the subtitle

*`DialogSeverity.critical`, `View.dialogIcon(_:)`, `View.navigationSubtitle(_:)`*

- **Critical severity** is macOS's large caution symbol. Shipped: the
  dialog's border and title in the palette's warning colour, unless the alert
  was given colours of its own. A `⚠` before the title would say it in a
  glyph too, but U+26A0 is drawn one or two cells wide depending on the
  terminal, so it wants a `Terminal-compatibility.md` measurement and the
  chrome-glyph fallback first (an hour with the probes).
- **The dialog icon** sits at the leading edge of the message: an SF Symbol as
  its glyph, a raster image fitted into 8×4 cells. macOS draws it above the
  title in the new alert style and beside it in the old; beside the message
  costs no extra rows.
- **The subtitle** follows the title on the navigation bar's one row, in the
  secondary colour and truncating first; macOS puts it under the window title.
  A second bar row would vary the bar's height, which the stack's layout
  forbids (`NavigationStack.barHeight`).

Each is a one-line change if you would rather the other drawing.

### B42. A resizable image stretches; one that isn't still fits; caps keep the fitted scale

*`Image.resizable(capInsets:resizingMode:)`, `Image.ResizingMode`*

**Shipped:** `.resizable()` fills the frame, aspect ignored, as SwiftUI's does
(measured on macOS 15), unless a content mode around it keeps the aspect, so
the common `.resizable().scaledToFit()` draws exactly as before. Cap insets
are in source pixels; the caps keep the scale at which the whole image fits
the frame, and the middle stretches, or for `.tile` repeats at that scale.

**What differs, and what a fuller version would cost:**

- An image that is **not** resizable fits what it is offered, where SwiftUI
  draws it at its pixel size. A terminal has no pixel size in cells (the
  compatibility doc's image sizing note). A natural size would need a
  pixels-per-cell figure: the cell pixel size the terminal reports
  (`imageCellPixels`) would give one where it is reported. That is about half
  a day, but it would make every existing `Image` without a frame change size,
  so it is a design change, not a fix.
- On an axis offered a scroll view's natural-extent budget, a resizable image
  takes the extent its aspect gives it, not its pixel size, for the same
  reason.
- An image drawn in slices (with caps, or tiled) draws as cells even where the
  terminal shows pictures. Sending the sliced pixels as a picture is about two
  hours: the picture's signature would have to name the box and the insets.

### B43. A `CGImage` or `NSImage` is drawn out once, and its address names it

*`Image(_:scale:orientation:label:)`, `Image(decorative:scale:orientation:)`,
`Image(nsImage:)`, `Image.Orientation`*

**Shipped**, behind `canImport(AppKit)` (A18's practice), with
`Image.Orientation` everywhere. The pixels are drawn out the first time the
image is drawn. The orientations' raw values and turns were measured on
macOS 15. `scale` and `label` are accepted and change nothing.

**What differs:** the image's identity is its object's address, kept unique
by holding the object for as long as a view draws it. An `NSImage` drawn into
in place after it was first drawn keeps its first pixels. Noticing that would
mean hashing the pixels at every `body`, which costs time in proportion to
the image's size on every frame.

### B44. A cell is one line unless its column says more

*`TableColumn.init(_:content:)` and every other initializer that takes a
`content:` closure*

SwiftUI grows each row to its tallest cell. Measured: a cell holding a
`VStack` of two `Text`s makes a 40-point row where single-line rows are 24
(`NSTableView.usesAutomaticRowHeights` is on). A long `Text` in a narrow column
does not wrap; it stays one row high and truncates.

**Shipped:** every column is one line unless its `lineLimit(_:)` — TUIkit's own
column modifier, which existed before this wave for key-path columns — allows
more. A view cell is rendered at the column's width and the limit's height, and
anything below the limit is clipped. With `.lineLimit(2)` the two-`Text`
`VStack` draws both lines, as SwiftUI's does. A `Text` cell under a limit above
1 wraps, which SwiftUI's does not; that matches what a key-path column under
the same limit has always done here.

**The fuller version** is automatic row heights: a view column with no stated
limit grows the row to the view's natural height. The price is the multi-line
row path for every table that has a view column. A single-line table answers
its size without building a row; a multi-line one measures every row below 256
rows (and samples above), and measuring a view cell means rendering it. So a
table that uses a view column for a coloured status `Text` would pay for
measuring every row, every frame, to learn that each is one line high. A middle
road: grow rows automatically only where the column's view is not a `Text` —
`VStack`s and the like, which are the cases that are actually taller.
Roughly a day, plus a measured A/B on `table` and `table-churn`.

### B45. Column customization is the app's to change; no gesture changes it yet

*`TableColumnCustomization` (all members), `TableColumnCustomizationBehavior`,
`TableColumnContent.customizationID(_:)`, `.defaultVisibility(_:)`,
`.disabledCustomizationBehavior(_:)`, the eight `columnCustomization:`
initializer keys*

On macOS a table bound to a `TableColumnCustomization` lets the user reorder
columns by dragging their headers, resize them by dragging the dividers, and
show or hide them from the header's context menu (measured: column reordering
is enabled only with a binding; resizing always). The binding records what the
user did, so it can be persisted.

**Shipped:** the whole vocabulary, and everything that does not need a
gesture. A column's default visibility hides it, with or without a binding —
measured, SwiftUI does the same. A bound customization shows and hides columns
by identifier, reads `.automatic` for anything nothing stated, encodes and
decodes (in TUIkit's own encoding: SwiftUI's is private), and persists through
`@SceneStorage` or `@AppStorage` with no default written, as Apple's sample
does. A stated column order, which only decoding can produce today, is
applied. `disabledCustomizationBehavior(_:)` is recorded with the column; with
no gesture to disable it takes nothing away, and it never restricted the app
in SwiftUI either.

**The fuller version** is the three gestures, each gated by the disabled
behaviors:

- **Visibility**: a column menu from the header — a right-click (or
  Ctrl-click, see the context-menu notes) and a key chord on the focused table
  — listing the identified columns with a mark, toggling one. Half a day: the
  menu engine and the row chords exist.
- **Reorder**: drag a header, and a chord pair to move the focused column
  left and right, which first needs a focused-column notion the table does not
  have. A day.
- **Resize**: drag the gap between two headers within the column's bounds, and
  a chord pair. A day, plus a decision on whether a resized width persists in
  the customization (SwiftUI's does).

### B46. A control in a view cell answers the keyboard, not the pointer

*`TableColumn.init(_:content:)` and every initializer that takes a
`content:` closure*

A view cell is rendered into the row's line, which carries the cell's
characters and not its mouse regions. A `Button` or `Toggle` in a cell is a
Tab stop like any other — Tab reaches it, Return or Space presses it — but a
click on it selects the row instead (measured on this branch: a click left a
`Button` in a cell unpressed; Tab then Return pressed it). A `.contextMenu` or
`.onTapGesture` on a cell's view is dropped the same way.

**Shipped:** the keyboard route, which every control has.

**The fuller version** carries each drawn cell's hit regions into the table's
buffer, offset to the cell's column and the row's band, so the control takes
the click and the row takes clicks elsewhere. The row memo would keep the
regions with the line it serves, or a row holding regions would not be kept.
Half a day, plus a measured A/B on `table` for the memo change.

### B47. A `Group` as a table's only column statement needs the key path's root

*`Group.init(content:)` for `TableColumnContent`*

`Table(people) { Group { TableColumn("Email", value: \.email) } }` does not
type-check here — "cannot infer key path type from context" — where SwiftUI
compiles it. The builder and the `Group` initializer are SwiftUI's,
signature for signature; with a second statement beside the `Group`, or a
root on the key path (`\Person.email`), it compiles.

**Shipped:** everything else about `Group` of columns.

**The fuller version** finds which of TUIkit's other `Group` initializers
(views, rows, commands, tab content) takes the solver's attention in that
one shape and disfavours it. Half a day, most of it reducing the case.

### B48. On Linux, a span of a month or more is spelt in English

*`Text(_:style: .relative)` and `.offset`; `SystemFormatStyle.DateOffset`*

SwiftUI spells a span in units: `2 min, 5 sec`, `1 yr, 3 mths`, `−2 minutes`.
Under a month TUIkit spells them with Foundation's `Duration.UnitsFormatStyle`,
which is localised, pluralised and list-joined on every platform (`1 Std.,
2 Min.` in German, as SwiftUI draws it). `Duration` has no years or months,
though. On Apple platforms those go through `Date.ComponentsFormatStyle`,
which matches SwiftUI's strings. The open-source Foundation declares that type
with no initialiser (only its `Field` exists), so on Linux years and months are
spelt from a small English table, CLDR's English abbreviations included
(`yr`/`yrs`, `mth`/`mths`).

**Fuller version:** the unit names for years and months (wide and abbreviated,
one and other) in the framework's own translation tables, joined with each
language's list pattern. About sixteen strings for each of the seven
languages, plus plural rules for French (where 0 is singular) and none for
Japanese and Chinese. Half a day; worth it only if an app on Linux shows
spans that long in a language other than English.

### B49. `SystemFormatStyle`: where the rules go beyond the measurements

*`SystemFormatStyle.Timer`, `.Stopwatch`, `.DateOffset`, `.DateReference`*

The four styles reproduce every reading measured (about 200, pinned in
`SystemFormatStyleClockTests` and `SystemFormatStyleDateTests`). Between the
measurements, these were chosen:

- **`DateReference`'s absolute form is drawn in the calendar's time zone.**
  SwiftUI's keeps a zone of its own beside the calendar, set from the current
  zone and not reachable through its API; `calendar(_:)` with a calendar in
  another zone therefore moves TUIkit's absolute form and not SwiftUI's. With
  the default calendar the two agree.
- **`now`.** Foundation's anchored relative style says "this minute" (or
  "this hour") where SwiftUI's reference says "now"; TUIkit says "now" when
  the finest allowed unit is a minute or an hour and the offset rounds to
  nothing in it. With seconds allowed Foundation says "now" itself; with days
  the finest, "today" is left alone (unmeasured).
- **`DateOffset` on a clock face** only when exactly minutes and seconds are
  allowed. SwiftUI's documentation says hours, minutes and seconds use it too;
  measured, with two fields, they did not, and three fields were not tried.
- **Boundaries.** `discreteInput(after:)` and `(before:)` return the instant the
  reading changes, at a boundary or one representable `Date` past it. SwiftUI's
  `before` sometimes returns the boundary itself, where the reading has not yet
  changed, which its protocol allows; TUIkit's never does. `DateReference`
  turns between its forms half a second before a period begins (the point of
  reference is rounded to the second), where SwiftUI's turn at a new year was
  measured at the year's first instant.

**Fuller version:** a macOS 26 measurement pass over the same probes, and the
three-field clock face. An hour each.

### B50. On macOS, SwiftUI's own `.offset(to:)` and the rest are visible beside TUIkit's

*`FormatStyle.offset(to:…)`, `.reference(to:…)`, `.timer(countingDownIn:…)`,
`.timer(countingUpIn:…)`, `.stopwatch(startingAt:…)`*

TUIkit imports AppKit publicly (its `NSColor` bridges are public API), and
from the macOS 15 SDK AppKit imports SwiftUICore. Until an app opts into
Swift's member-import-visibility rule, an extension member of any module
imported however indirectly is visible, so every app that imports TUIkit sees
SwiftUICore's five statics on Foundation's `FormatStyle` beside TUIkit's. The
types do not leak; these extension members do. Measured with a two-module
probe:

- both on `FormatStyle`: `Text(.currentDate, format: .offset(to: d))` is
  ambiguous and does not compile;
- TUIkit's only on `DiscreteFormatStyle`: a context that takes any
  `FormatStyle` picks SwiftUI's, which then fails to LINK (SwiftUICore admits
  no direct clients);
- both (shipped): a `DiscreteFormatStyle` context picks TUIkit's (the
  refining protocol's extension is the more specialised), and a plain
  `FormatStyle` context is ambiguous — a compile error, not a link error.

So TUIkit declares each static twice, and takes these styles as
`DiscreteFormatStyle` everywhere: `Text(_:format:)` over a time data source
already does, and `Text(_:format:)` and `appendInterpolation(_:format:)` for
an `AttributedString` output gained a discrete overload beside the
`FormatStyle` one. What stays ambiguous on macOS is a `FormatStyle` context
outside TUIkit, such as `Date.now.formatted(.offset(to: d))`; spelling the type
(`SystemFormatStyle.DateOffset(to: d)`) settles it. Linux has no SwiftUICore.

**Fuller version:** move the AppKit bridges (`Color(nsColor:)`,
`NSColor(_:)`, the `CGColor` pair) into a module of their own, so TUIkit can
import AppKit `internal`ly and nothing of SwiftUICore reaches an app. That
fixes this for every Foundation extension SwiftUI declares, not only these
five, at the price of one more product to import for the bridges (half a day
with the documentation). Your call whether that is worth it now; nothing else
in this wave needs it.

### B51. A live text read for its string is read once, when it is built

*`Text(_:style:)`, `Text(timerInterval:…)`, the live interpolations,
`Text(_:format:)` over a `TimeDataSource`*

A live `Text` draws its words at each frame. But some of TUIkit's API takes a
`Text` only for its string — `navigationTitle(Text)`, `help(Text)`,
`dismissalConfirmationDialog`'s title — and a `LocalizedStringKey` handed to a
control other than `Text` (a button's title) is resolved to a string where the
control is built. Those read a live text or a live interpolation once, as it
read when built; it moves only when the view around it is rebuilt. SwiftUI
keeps them live, since its titles are `Text` all the way down.

To give those consumers a reading at all, a live text formats once when it is
built, as well as at each frame it is drawn. Only live texts pay it (about
6 µs for a unit spelling, 30 µs for `.time`/`.date`, which use a
`DateFormatter`).

**Fuller version:** the string-taking consumers keep the `Text` and draw it,
which each of them could (a title is drawn by a `Text` in the end); a title
that changes would then also have to re-measure the bar it sits in. About two
hours a consumer, and none has asked. **A/B owed:** the build-time reading
could be deferred to the first consumer that asks, saving it for every live
text drawn only as a view — worth measuring on a list of a few hundred
`Text(date, style: .relative)` rows before deciding.

### B52. A custom transition's body is drawn at each frame's point between its phases

*`Transition` (`body(content:phase:)`, `Content`, `properties`,
`animation(_:)`, `combined(with:)`, `apply(content:phase:)`),
`TransitionPhase`, `TransitionProperties`, `PlaceholderContentView`,
`AnyTransition.init(_:)`, `AnyTransition.modifier(active:identity:)`,
`View.transition(_:)` for a `Transition`*

**How SwiftUI does it.** A transition's body is evaluated at three discrete
phases. On insertion it is shown at `.willAppear` and then "immediately moved
to the `identity` phase" under the change's animation; on removal it goes from
`.identity` to `.didDisappear`. Nothing about the body is continuous: what
moves are the animatable modifiers inside it, each interpolated between the
value it had at one phase and the value it has at the other. "If no animatable
change is applied, then the transition will be a no-op."

**How TUIkit had it.** A transition was a value — `AnyTransition`'s closed set
of effects — applied to the view's rendered buffer as a function of one number,
how present the view is (0 absent, 1 there, above 1 while a spring overshoots).
An insertion reads that number from the animation store as the view arrives; a
removal leaves a closure behind every frame, "here is what I look like part-way
gone", which whatever holds its slot plays out over the picture the view last
drew (`DepartureStore`). All of that stays exactly as it was.

**What shipped: a custom body is drawn by scrubbing it.** For a presence `p`
on any frame of an arrival or a departure, the body is rendered twice:

1. **Record**, at the end phase (`.willAppear` arriving, `.didDisappear`
   leaving), with the content standing in as an empty box of its own size.
   Every animatable value the body produces — an `Animatable` view or
   modifier's data, and the colours `.foregroundStyle`, `.background` and
   `.border` resolve — is noted, keyed as the animation store keys it (place
   in the tree, owning type, slot), and nothing is drawn.
2. **Draw**, at `.identity`, with the real content, and each of those values
   replaced by `end.interpolated(towards: identity, amount: p)`.

That is the same arithmetic the animation store performs when a value animates
(`from.interpolated(towards: to, amount: curve(t))`), with `p` already being
`curve(t)`, so the picture is the one SwiftUI's per-modifier interpolation
gives. Both passes go through one hook at the top of the store's lookup, so a
scrubbed value never reaches, or disturbs, the store's own records. A value
built FROM one drawn part-way — inside the body of an animatable modifier,
evaluated at its interpolated data — is drawn as built, not interpolated a
second time; what a placeholder draws (the view a modifier is applied to) is
not built from the modifier, and is scrubbed on its own account.

Everything else is reused rather than rebuilt: the arrival phase and its
explicit animation, the departure slot and its timing, a removal starting
mid-insertion from where the arrival had got to, a spring's overshoot (`p`
above 1 extrapolates, so an `.offset` in a body bounces past its slot and an
`.opacity` stops at opaque, both as the built-ins do), and the rule that only
an animated change transitions.

**The content is live while the view is present.** The placeholder draws the
real view, at the transition's own identity (so its `@State` is where it would
be without the transition), under the environment the body gives it — a body's
`.foregroundStyle` or `.disabled` reaches it, as in SwiftUI. While the body is
being recorded the placeholder draws nothing, so the content's side effects
(focus, hit regions, `onAppear`) happen once a frame, as they always have.
At rest the body is drawn at `.identity` every frame: SwiftUI applies it for as
long as the view is visible, and a body is allowed to leave something there.

**Where TUIkit cannot follow SwiftUI, and why.**

- **A departing view's content is a picture.** A removed view does not exist
  any more — that is what `DepartureStore` is for — so while it leaves, the
  body is drawn around the cells the content drew on its last frame. The
  body's own modifiers still move: its opacity, offset, colours. What the body
  would have changed *inside* the content (an environment value that differs
  between `.identity` and `.didDisappear`) does not change any more once the
  view has gone.
- **The slot is the size of the `.identity` body.** A body that changes the
  view's size between phases (`.frame(height: phase.isIdentity ? nil : 0)`,
  a collapse) is drawn inside the size it has at rest, rather than re-laying
  out its siblings on every frame. TUIkit's transitions have never moved
  their neighbours (see `AnyTransition`); this is the same rule applied to a
  custom body.
- **A body that changes its structure between phases does not animate the
  difference.** A value is interpolated only where both renders produced it
  at the same place; a modifier present at one phase and not the other is
  drawn as the `.identity` render has it. SwiftUI asks for the same
  ("Transitions should not use any identity-affecting changes like `.id`,
  `if`, and `switch`").

**The built-in transition types** (`OpacityTransition`, `MoveTransition`,
`OffsetTransition`, `ScaleTransition`, `SlideTransition`, `PushTransition`,
`IdentityTransition`, `AsymmetricTransition`) have real bodies, built from one
animatable modifier that applies TUIkit's own effect at the body's presence —
so `OpacityTransition().apply(content: v, phase: phase)` inside an app's own
transition fades exactly as `.opacity` does. Erased to `AnyTransition` (which
is what `View.transition(_:)` does with any `Transition`), they keep the
buffer fast path; only a transition with a body of the app's own takes the
two-pass route.

**What it costs.** Two body renders a frame while a custom transition plays
(the first draws no content); one at rest, which is what any `ViewModifier`
body costs. The built-ins cost what they did.

**The fuller version.** Animate the layout too: measure the body at the
interpolated values each frame, so a collapsing transition closes its gap as
it goes. That is a re-layout of the transition's container per frame — the
cost the buffer-based design exists to avoid — and needs the measure walk to
scrub as well, which the memoised measure path makes delicate. About two days.
I would wait for a port that needs it.

### B53. `TransitionProperties.hasMotion` is recorded, and nothing reads it yet

*`TransitionProperties`, `TransitionProperties.hasMotion`,
`TransitionProperties.init(hasMotion:)`, `Transition.properties`*

SwiftUI: "When this behavior is included in a transition, that transition will
be replaced by opacity when Reduce Motion is enabled." TUIkit reads no
reduce-motion setting (O1 of the refusal review), so Reduce Motion is never on
and the replacement never happens — which is what SwiftUI does on a Mac with
the setting off. The built-ins report the values measured on SwiftUI: opacity
and identity have no motion, everything else has, and a combined or asymmetric
pair has motion if either half does.

**The fuller version** comes with O1 (b): when the host's reduce-motion
setting (or `TUIKIT_REDUCE_MOTION`) is on, `View.transition(_:)` swaps a
transition with motion for `.opacity`. A few lines once the setting exists.

### B54. A scale transition uncovers from its anchor, and a scale above 1 draws the view whole

*`ScaleTransition` (`init(_:anchor:)`, `scale`, `anchor`),
`Transition.scale`, `Transition.scale(_:anchor:)`,
`AnyTransition.scale(scale:anchor:)`*

TUIkit's `.scale` already reveals the view from its anchor a whole cell at a
time, there being no sub-cell rendering to shrink. The scale factor is now
where that reveal starts: `.scale(0.5)` shows half the view at once and
uncovers the rest. `.scale` itself is `ScaleTransition(1e-5)`, SwiftUI's own
value (measured) — nothing, in whole cells.

A factor above 1 asks for the view to start larger than its slot. A cell grid
cannot draw that: the reveal is clamped at the whole view, so the transition
draws the view whole from the first frame. `opacity` above 1 is clamped the
same way in SwiftUI itself.

TUIkit's own spelling, `AnyTransition.scale(anchor:)`, was not SwiftUI's and is
gone; `scale(scale: 0, anchor:)` is the same transition.

**The fuller version** would draw an oversized start by cropping the view to
its middle and widening the crop as it settles — a zoom-out rather than a
grow. Nothing in TUIkit crops from the middle today; half a day, and I would
wait for someone to ask.

### B55. `tracksVelocity` is recorded, and no velocity is carried; `isContinuous` is set by TUIkit's own continuous controls

*`Transaction.tracksVelocity`, `Transaction.isContinuous`*

**`tracksVelocity`.** SwiftUI accumulates the velocity of values changed under
such a transaction, so a later animation can start moving at that speed.
TUIkit's animations are closed-form functions of elapsed time that start at
rest — a spring retargeted mid-flight already restarts from where its picture
is, without its speed — so there is nothing to track, and the flag is a value
the transaction carries for whoever reads it. This is the one place the
"retargets at rest" deviation of every TUIkit spring shows up as a property;
the Wave 17 review (W6) asked for it to be documented in one place rather than
used to refuse spellings, and B58 (the spring animations) points here
too.

**`isContinuous`.** SwiftUI sets it when "a continuous action created the
transaction" — dragging a slider, holding a stepper. TUIkit now sets it on the
writes its own controls make that way: a press and drag on a `Slider`'s track,
and the repeats of a held arrow (`Slider`, `Stepper`) or a repeating
`Button` (the first action of the press is a click, and is not continuous).
A key the terminal repeats arrives as separate presses with nothing to say
they are one hold, so a held arrow KEY is not continuous. Setting the flag
makes the write an explicit transaction, which — like any `withTransaction` —
takes over from an animated change made earlier in the same frame.

**The fuller version** of `tracksVelocity` is O3's: velocity-preserving
retargeting needs integrated animations, the `CustomAnimation` question.

### B56. When a completion fires: the pass that shows the change decides, and a spring logically completes at its pace

*`AnimationCompletionCriteria` (`.logicallyComplete`, `.removed`),
`Transaction.addAnimationCompletion(criteria:_:)`,
`withAnimation(_:completionCriteria:_:completion:)`,
`Animation.logicallyComplete(after:)`*

SwiftUI fires a completion "when the animations created with this
transaction are all complete", exactly once, and "immediately after `body`"
if the changes created none.

**Shipped.** A completion rides the transaction onto the state change made
under it; the frame that renders the change starts its animations, and the
stores report each one they start (an animated value, an arriving transition,
a departing one) for that pass only. Then:

- **Nothing changed** in `body` (no state change claimed the completion): it
  runs as `withTransaction` returns.
- **Something changed but nothing animated:** it runs when that frame's pass
  ends.
- **`.logicallyComplete`:** when the latest logical completion among the
  started animations has passed. A curve completes at its end. A spring
  completes at the end of its pace — the `duration:` it was made with — and
  settles after that; SwiftUI calls that "the long tail". `.logicallyComplete
  (after:)` brings the point forward (it scales with `speed`, as the delay
  does), never past the end. A later change does not move it.
- **`.removed`:** when the latest end has passed and none of the values the
  pass started is still animating, so a retarget makes it wait for the new
  animation too.
- **A value whose view has left** is removed, so its completion fires
  whatever the deadlines say; a `repeatForever` animation still on screen
  never completes, as in SwiftUI.

Two transactions in one frame render under the last one (the rule TUIkit
already had), but each keeps its completion: the pending completions are
collected separately from the pending transaction.

**Readings, not measurements.** That a spring logically completes at its
perceptual duration is from SwiftUI's description of a spring's `duration`
("the perceptual duration, which defines the pace of the spring"); a
completion's timing could not be measured with an offscreen hosting view.
"The animations created with this transaction" is read as every animation the
change's frame starts — an unrelated `.animation(_:value:)` whose value moved
in the same frame is included.

**Not honoured:** a completion added by a view's `transaction(_:)` modifier
while rendering. No change was made under that transaction, so nothing claims
the completion and nothing runs it. SwiftUI documents no such use either.

### B57. `UnitCurve` is SwiftUI's arithmetic, except where its answers contradict its documentation

*`UnitCurve` (`value(at:)`, `velocity(at:)`, `inverse`, `bezier(startControlPoint:endControlPoint:)`,
the eight named curves), `Animation.timingCurve(_:duration:)`*

The Bézier curves share the solver an `Animation`'s timing curve uses (the
Wave 17 review asked for one formula, not two), and match SwiftUI's values and
velocities to the sixth place (measured, `w12/probe/p3.swift`). Two readings
differ from what SwiftUI answers, in the documentation's favour:

- **Out-of-range input is clamped**, as `value(at:)` and `velocity(at:)`
  document. SwiftUI clamps its Bézier curves, but not `.linear` (1.5 gives
  1.5) or the circular ones (1.5 gives NaN, -0.5 a mirrored value).
- **`circularEaseInOut.inverse` is the curve with x and y swapped**, as
  `inverse` documents: level in the middle, steep at the ends. SwiftUI
  answers `circularEaseInOut` itself, whose values are not an inverse at all.

Where a curve is vertical — `circularEaseIn` at its end, the circular in-out
at its middle — the velocity is infinite, as in SwiftUI. Where a Bézier's
control point sits on its end point the tangent vanishes, and SwiftUI answers
1 (`easeOut` at 0) or 0 (`easeIn` at 1, the quotient of two rounding errors)
rather than the limit the curve approaches (1.72 for both). TUIkit answers
the same, by the same arithmetic: a keyframe track carries a linear
keyframe's end velocity into the cubic keyframe after it, and the two
frameworks' tracks agree only if these do.

A circular curve is a new case of the animation curve, so
`Animation.timingCurve(.circularEaseIn, duration:)` moves along the circle;
a Bézier or `.linear` builds the animation `timingCurve(_:_:_:_:duration:)` and
`linear(duration:)` already build, and compares equal to it.

### B58. `Spring` is SwiftUI's numbers, two quirks kept and one not; a spring animation keeps no velocity across a retarget

*`Spring` (its four initialisers, `duration`, `bounce`, `response`,
`dampingRatio`, `mass`, `stiffness`, `damping`, `settlingDuration`, `value`,
`velocity`, `force`, `update`, `settlingDuration(…)`, `.smooth`/`.snappy`/
`.bouncy` and their tunable forms), `Animation.spring(_:blendDuration:)`,
`spring(duration:bounce:blendDuration:)`, `spring(response:dampingFraction:blendDuration:)`,
`interactiveSpring` (all three), `interpolatingSpring` (all four)*

The Wave 17 review (W6) found the refusal of all of these to be a judgement,
not a limit: TUIkit already drew springs in closed form. `Spring` is that
closed form made public — one implementation (`SpringMotion`) behind both the
type's arithmetic and the curve a spring animation is drawn with — and every
number was checked against SwiftUI's `Spring` on a probe
(`w12/probe/p4.swift`, `p5.swift`): values, velocities with and without a
starting velocity in all three damping regimes, force, `update`, the
settling durations, the conversions, the presets.

**Quirks kept, because ported arithmetic reads them:**

- An overdamped spring's `stiffness` reads `(2ζ² − 1)` times the stiffness it
  moves with, and `force` uses it.
- A critically or overdamped spring's settling duration is found in steps of
  a tenth of a second (0.8 s for the default spring); an underdamped one's is
  the bound `ln((|y₀| + |v₀ + ζω·y₀|)/ε)/(ζω)`.
- `init(settlingDuration:dampingRatio:epsilon:)` solves a different relation
  from the one `settlingDuration` answers by, so the spring it makes reports
  a longer settling duration than it was asked for (1 s asks, 1.25 s
  reported, at ζ = 0.8), and a ratio above 1 is treated as 1.

**A quirk not kept:** SwiftUI's overdamped `velocity(…)` reads exactly one
more than the derivative of its own `value(…)` (1 at rest at t = 0). TUIkit
answers the derivative.

**Bounce at or below −1** is NaN in SwiftUI; here it stops at −0.999, a spring
too sluggish to visibly arrive, rather than a NaN on its way to a cell.

**Retargeting.** SwiftUI's `spring` hands its velocity to the next spring on
the same value, blending the durations over `blendDuration`; its
`interpolatingSpring` adds overlapping animations so velocity is preserved.
TUIkit's animations are functions of elapsed time from a start at rest: a
change that retargets a running spring starts the new one from where the
picture is, without the speed it had. So `blendDuration` has nothing to blend,
and `interpolatingSpring`'s `initialVelocity` is honoured for the change it
is given to — it moves the start of the curve and lengthens the settling the
loop waits for — but not inherited by the next. This is the deviation every
TUIkit spring already had (B55 records `tracksVelocity` against it); the
`interactiveSpring` presets are, accordingly, the quick springs their numbers
describe.

**The fuller version** is velocity-preserving retargeting: store the
velocity at retarget and start the next closed form with it
(`SpringMotion` already takes one). For springs alone that is a day — the
store records where the picture is; it would also record how fast — but a
curve retargeting into a spring, or a spring into a curve, has no velocity
model, which is O3's question.

### B59. Visual effects: the five a cell can show, drawn by the `View` modifiers of the same names

*`VisualEffect`, `EmptyVisualEffect` (`init()`, `AnimatableData`),
`View.visualEffect(_:)`, `VisualEffect.offset(_:)`, `offset(x:y:)`,
`opacity(_:)`, and — moved out of the map's pixel-effects family, as the Wave
17 review (P14) found they should be — `brightness(_:)`, `contrast(_:)`,
`saturation(_:)`, `grayscale(_:)`, `hueRotation(_:)`*

**Shipped.** The content is drawn, the closure is handed a `GeometryProxy` of
the size it drew at, and the effect it returns is applied to the drawing.
Each effect is drawn by the `View` modifier of the same name around the
drawn buffer, so `.visualEffect { $0.grayscale(1) }` is exactly
`.grayscale(1)` (pinned by a test per effect); a chain applies the later
effect over the earlier. The effect is `Animatable` and animates as a
modifier does, keyed by its place in the tree. Effects never change layout.

**Where it differs.**

- **The proxy's frame is local.** `frame(in: .global)` answers as `.local`
  does, which `GeometryProxy` already documents (A2 is the question of making
  global geometry real). SwiftUI's own example, an offset that follows the
  view's global position, therefore draws no offset here.
- **The closure is main-actor isolated** where SwiftUI's is only `@Sendable`.
  TUIkit's `Animatable` is a main-actor protocol (the decision recorded in
  `Animatable.swift`), so building an effect is main-actor work. A closure
  literal — the only way the API is used — takes on the isolation it is
  declared with, so SwiftUI's source compiles unchanged.
- **Offsets are whole cells**, as `View.offset` is (§2.1 of the
  compatibility doc).

**Not offered** — so asking fails to compile: rotation, scale, 3D rotation
and arbitrary transforms wait on Wave 16 (A39); blur, blend modes and
the shader effects stay in the map's pixel-effects family.

### B60. Keyframe timelines follow SwiftUI's curves, measured; the animator views stay with O2

*`KeyframeTimeline` (`init(initialValue:content:)`, `duration`, `value(time:)`,
`value(progress:)`), `Keyframes`, `KeyframeTrack`, `KeyframeTrackContent`,
`KeyframesBuilder`, `KeyframeTrackContentBuilder` (and `Conditional`),
`LinearKeyframe`, `CubicKeyframe`, `SpringKeyframe`, `MoveKeyframe`,
`Never: Keyframes`*

The Wave 17 review (P13) found the timeline side of the keyframe family
wrongly refused: these are pure functions of time with no rendering at all,
and `KeyframeTimeline` cannot be written without them. `KeyframeAnimator` and
`keyframeAnimator` — the views that play a timeline — stay with O2.

**Shipped,** with every curve rule taken from SwiftUI's own timelines
(`w12/probe/p6.swift`, `p7.swift`) and pinned by tests to six places:
adjacent cubic keyframes form a Catmull–Rom spline at rest at both ends; a
cubic keyframe starts at the velocity the keyframe of another kind before it
ended at, and ends at the next one's starting velocity; a named velocity
wins on its own side of a junction only; a spring keyframe without a
duration runs until it is within 0.0001 of its target (an absolute
threshold, so a larger change takes longer), and one cut short hands on the
value and velocity it reached; a move leaves the value at rest; tracks run
together from the initial value and the last to write a property wins.

**Where it differs.**

- **Main-actor isolated.** The protocols, builders and the timeline's
  initialiser and samplers are, because TUIkit's `Animatable` is (its values
  are read and written through `animatableData`). SwiftUI's are
  nonisolated. Code that builds a timeline in a view, a body or a `.task`
  compiles unchanged; one built off the main actor does not.
- **A time before the start is the start.** SwiftUI clamps its linear and
  cubic segments there, but evaluates a spring backwards (−58.5 at −0.5 s for
  a bouncy spring to 1).
- **A zero-length linear or cubic keyframe arrives at once**, where SwiftUI
  divides by its zero length and answers NaN.

### B61. A content transition dissolves everything the modifier wraps

*`ContentTransition` (`.identity`, `.opacity`, `.interpolate`,
`.numericText(countsDown:)`, `.numericText(value:)`), `View.contentTransition(_:)`,
`EnvironmentValues.contentTransition`,
`EnvironmentValues.contentTransitionAddsDrawingGroup`*

The Wave 17 review (W4) found the refusal ("a cell holds one glyph with no
alpha") overtaken by opacity compositing. **Shipped:** where the modifier is
written, a change to what its content draws, made under an animation, draws
the new content over the old at the animation's progress through the opacity
compositor: colours blend and each cell's glyph changes half way, so a cell
whose character is the same keeps it and moves only its colours. That is
`.interpolate` here (SwiftUI's "matching glyph pairs" interpolate, and the
rest use its documented opacity fallback); `.opacity` and both
`.numericText` forms draw the same dissolve (SwiftUI's rolling digits are
promised only "in certain environments"); `.identity` draws the change at
once. A change in mid-dissolve dissolves from what is on screen. The dissolve
counts as an animation for completions.

**Where it differs.** SwiftUI's leaf views read the environment value and
each animates its own content. Here the modifier dissolves its whole
subtree's drawing — identical cells dissolve into themselves, so only what
changed is seen to move, but an inner `.contentTransition(.identity)` does
not exempt its part, and the view takes its new size at once (a shrinking
drawing loses its edges immediately). `contentTransitionAddsDrawingGroup` is
a rendering hint with no visible contract (a drawing group changes how
SwiftUI composites, not what it shows) and is kept for whoever reads it. The
symbol-effect content transitions wait on A35.

**The fuller version** is A40's second option: the dissolve inside `Text`
and `Image`, reading the environment, which also gives the leaf-level
semantics above.

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

### C4. `KeyEquivalent.clear`

*`KeyEquivalent.clear`*

SwiftUI's `.clear` is AppKit's Clear key, U+F739: the keypad key in Num
Lock's position on a full-size Mac keyboard. A shortcut or `onKeyPress` on it
fires only if a terminal sends that key as a key of its own. The legacy
encodings TUIkit parses have no sequence for it, and the parser has nothing
to map to it. So `.clear` would name a key no event can carry, and a
shortcut on it would compile and never fire. Rule 2 says leave it out.

Not byte-captured: this machine has no extended keyboard. If a terminal turns
out to send the key, distinctly from Num Lock, the parser gains a case and
this entry goes. The kitty keyboard protocol of A4 is the likeliest
route: it reports keypad keys by their own codes.

### C5. `HelpLink(anchor:)` and `HelpLink(anchor:book:)`

*`HelpLink.init(anchor:)`, `HelpLink.init(anchor:book:)`*

Both open an anchor in an Apple Help book, through AppKit's `NSHelpManager`
and the Help Viewer. A terminal app has no help viewer to open, and Linux and
Windows have no help books. `HelpLink(action:)` and `HelpLink(destination:)`
ship, so a help button that runs code or opens a URL ports as written.

### C6. `scrollInputBehavior(_:for:)` and `ScrollInputKind`

*`ScrollInputKind`, `View.scrollInputBehavior(_:for:)`*

`ScrollInputKind`'s values are watchOS's — the Digital Crown and the
double-tap hand-gesture shortcut — and the macOS SDK defines none. No macOS
source can name a kind, so none can call the modifier: declining it changes
what compiles for nobody. A terminal has neither input. What macOS code can
ask — may this view scroll at all — is `.scrollDisabled`, already the
`ScrollInputBehavior` map entry.

### C7. `ScrollView.showsIndicators`

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

### C8. `TypesettingLanguage`

*`TypesettingLanguage` (`.automatic`, `.explicit(_:)`),
`View.typesettingLanguage(_:isEnabled:)` and `Text.typesettingLanguage(_:isEnabled:)`
in both forms*

The language a run is typeset in sets its line height (taller for Thai, say),
its line breaking and its spacing. Line height is the terminal's row, and
spacing is whole cells. TUIkit's word wrapper breaks at spaces and at
characters a line cannot hold, whatever the language, so a language would
change none of the three, and accepting one would be the quiet no-op the
parity rules forbid. If the wrapper ever learns dictionary-based breaking
(Thai, Khmer and Lao have no spaces between words), this becomes its
modifier.

### C9. `@FocusedObject`, `focusedObject(_:)`, `focusedSceneObject(_:)`

*`FocusedObject` (and its `Wrapper`, `init()`, `wrappedValue`,
`projectedValue`), `View.focusedObject(_:)`, `View.focusedSceneObject(_:)`*

All three take an `ObservableObject`, the Combine-based family §2.3 of the
compatibility doc declines for the whole framework. The `@Observable` forms
SwiftUI offers beside them ship — `@FocusedValue(Model.self)`,
`.focusedValue(model)`, `.focusedSceneValue(model)` — so the map entries are
`differentShape`, naming those.

### C10. `OutlineSubgroupChildren`

*`OutlineSubgroupChildren`*

The content type of the `DisclosureGroup` that is SwiftUI's
`OutlineGroup<…, Subgroup>` for views — a type only ever written inside
`OutlineGroup`'s full generic signature. TUIkit's `OutlineGroup` declares
the three generic parameters that carry information and drops the two that
are always the same (`Parent` is `Leaf`; `Subgroup` is that one
`DisclosureGroup`), as its documentation records, so there is no subgroup
type for this to be the content of. Every `OutlineGroup` initializer, for
views and for table rows, is SwiftUI's; only spelling the type out by hand
differs.
