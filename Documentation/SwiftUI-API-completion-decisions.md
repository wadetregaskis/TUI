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

*`DismissBehavior`, `.interactive`, `.destructive`*

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
`SceneBuilder.buildOptional(_:)`, `SceneBuilder.buildLimitedAvailability(_:)`*

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
