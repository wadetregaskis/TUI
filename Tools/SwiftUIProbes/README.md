# SwiftUI probes

Small programs that record what SwiftUI does, so that TUI can do the same. These are the ones that TUI's
doc comments, tests and decisions files cite, by path, as the measurement behind a claim about SwiftUI's
behaviour; each is kept with what it printed. A few probes that only lane notes cite stay in the maintainers' working
notes, and a document that cites one of those names its folder there.

Each probe is a short Swift program compiled with `swiftc` against the macOS SDK and run on a Mac. Most host SwiftUI
views in an `NSHostingView`, in a borderless window placed off-screen, and print what they read back: the frames
views were given (through a `GeometryReader` or a `Layout`), how many subviews a container counted, which
`@State` values a body saw, which `update()` calls ran, the colour of the pixels SwiftUI drew down a column. Some
read the AppKit views SwiftUI made instead (an `NSTableView`'s rows, an `NSMenu`'s items), and a few print a value
with no view at all. What a probe printed is in a `.out` file of the same name; a probe with no `.out` file
reported its result in the document that cites it.

One folder, Swift runtime layouts, records the Swift runtime's own layouts that TUI's property walk reads,
with no SwiftUI involved.

They are evidence, not part of the package: SwiftPM, CI and SwiftLint do not see them, and no binary or other
build product is kept here. Nor are pixel dumps and renders (`.png`, `.tiff`, `.rgba`): the probes that made them
make them again. `Tools/TerminalProbes/` is the same idea for terminals.

## Where they ran

On the development Mac, an Apple-silicon VM running macOS 15.8 (15.8.1 where a note gives the point release;
SwiftUI 6.5.4), against the macOS 26.2 SDK of Xcode 26.3, between 2026-10-03 and 2026-10-19; where the notes name
the compiler, it was Xcode's Swift 6.2.4. API that is new in macOS 26 could not be run there, so no probe
measures it. Each folder below says what its citing documents state about the machine.

## Building and running one

Build with Xcode's toolchain, into a directory outside the repository, from the probe's folder:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd "Tools/SwiftUIProbes/Sections and subview counting"
# A program with @main is built together with its folder's shared files (common.swift, and scan.swift in
# "Pinned section headers and footers"):
xcrun swiftc -parse-as-library -target arm64-apple-macos15.0 common.swift b17.swift -o "$TMPDIR/b17"
"$TMPDIR/b17" | diff b17.out -     # no output: SwiftUI still does what was recorded

# A program of top-level code (no @main) is built alone:
cd "../Dynamic properties"
xcrun swiftc -target arm64-apple-macos15.0 dp.swift -o "$TMPDIR/dp"
OS_ACTIVITY_DT_MODE=YES "$TMPDIR/dp"   # the variable lets SwiftUI's runtime warnings reach stderr
```

A probe opens windows, so it runs in the logged-in user's session, where the window server is. Where a probe was
also built with `-D OPTCONF` (a retroactive `Optional: DynamicProperty` conformance), its second output is named
`…-optconf.out`. Re-run on 2026-10-12 on macOS 15.8.1: `b17` built from this folder as above printed `b17.out`
byte for byte.

To add one: give it a topic folder here (or join one), keep its source, its output and any notes, never its
binary, and cite it by its path, `Tools/SwiftUIProbes/<folder>/<file>`.

## The probes

Each folder says what its probes ask, what is in it, where it lived in the maintainers' working notes (commit
messages cite that path), and what cites it.

### Dynamic properties

- **Asks:** what SwiftUI does with `DynamicProperty.update()` in the cases a review questioned: a plain field, an
  optional one, an enum view, class properties held strongly, weakly and `unowned`, an observation read in
  `update()`, a metatype field beside a wrapper, and an enum view drawn blank and then with a payload (`dp.swift`,
  its cases numbered in `dp.out`); and how many fields the runtime's mirror reports for an enum
  (`enumfields.swift`: none, for one with three cases, two with payloads).
- **Ran:** macOS 15, 2026-10-10.
- **Was:** `DYNP/probe/`.
- **Cited by:** `Documentation/Historical/State and dynamic properties/Finding dynamic properties, and writing back what update() changes.md`;
  `Tests/TUIFoundationTests/DynamicPropertyTests.swift`, `Tests/TUIFoundationTests/ObservableInvalidationScopeTests.swift`. The
  probes of the next three folders reuse its harness.

### Dynamic property discovery

- **Asks:** which stored fields of a view SwiftUI visits for a `DynamicProperty`: a plain field, an optional, an
  existential (`any DynamicProperty`, `Any`), a generic, a modifier held or applied, a class, a `weak` field; and
  whether it runs a `ViewModifier`'s body when the body returns `content` unchanged. `notes.md` is the write-up:
  the answer, how discovery works, the measured matrix against TUI, and the divergences it found.
- **Files:** `op.swift` (built plain and with `-D OPTCONF`; `op.out`, `op-optconf.out`), `weak.swift`
  (`weak.out`), `passmod.swift` (`passmod.out`), `notes.md`. A second round, for the suspects of lane DYNV's bug
  hunt that `op.swift` did not measure (a property in a `let` field, one view value at two places, a class
  property's subclass, a modifier wrapped by `.transaction(_:)` or joined by `.concat(_:)`, a dead `unowned`
  field read first): `dv.swift` (`dv.out`) and `dv2.swift` (run as `./dv2 main` and `./dv2 deadfirst`, which may
  trap; `dv2-main.out`, `dv2-deadfirst.out`). `classmod.swift` (`classmod.out`, each case run on its own:
  `./classmod stored`, `applied`, `fresh`) asks what SwiftUI does with a class that is both a `DynamicProperty` and
  a `ViewModifier`: held in a view's field and never applied, its `update()` runs once per body of the view; applied,
  whether held in a field or made in the body, SwiftUI traps ("view modifiers must be value types").
  `twoplaces.swift` (`twoplaces.out`) draws one view value with a `@Namespace` at two places: each place has a
  namespace of its own.
- **Ran:** macOS 15.8.1, SwiftUI 6.5.4, 2026-10-10; the second round 2026-10-11; `classmod.swift` and `twoplaces.swift` 2026-10-19.
- **Was:** `DYNP/optional/`; the second round `DYNV/probe/`.
- **Cited by:** `Sources/TUIView/State/DynamicProperty.swift`,
  `Sources/TUIView/State/NestedPropertyBinding.swift`, `Sources/TUIView/State/PropertyPlans.swift`,
  `Sources/TUIView/State/State.swift`; `Tests/TUIFoundationTests/DynamicPropertyStateKeyTests.swift` and the other
  `DynamicProperty*Tests.swift` files, `Tests/TUIFoundationTests/StateSharedValueTests.swift`;
  `Documentation/Historical/State and dynamic properties/Finding dynamic properties, and writing back what update() changes.md`,
  `Documentation/Historical/State and dynamic properties/Finding dynamic properties, and writing back what update() changes.md`,
  `Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md`.

### Class properties held by several views

- **Asks:** what SwiftUI does with a class `DynamicProperty` holding a `@State`, a nested struct property with a
  `@State`, an `@Environment` and an `update()` counter, when one object is held by several views at once, by a
  view an `if`/`else` swaps, by `ViewThatFits` candidates, by `ForEach` rows one of which is removed, by a child of
  a view keeping the object in its own `@State`, and made anew with each view value; and whether its
  `@Environment(Model.self)` resolves (`cls.swift`, one case a process: `./cls two`, `swap`, `vtf`, `rows`, `held`,
  `perValue`, `envModel`; `cls.out`). And SwiftUI's model of "the views that read an object are its dependents":
  one `@Observable` shown by two views, one behind an `.equatable()` that always compares equal, written once
  (`memo.swift`, `memo.out`). Answers: `update()` runs before each holder's body, measured-only candidates
  included; `@State` inside the class is a constant and `@Environment` its default; an object made per view value
  starts afresh; `@Environment(Model.self)` there traps; the write to the observable redraws both views.
- **Ran:** macOS 15.8.1, SwiftUI 6.5.4, 2026-10-12; `cls.swift` against the macOS 15.5 SDK.
- **Was:** `DYNVCLAIM/swiftui-first/` (`cls.swift`) and `DYNVCLAIM/object-owned/swiftui/` (`memo.swift`).
- **Cited by:** `Sources/TUIView/State/PropertyWalk.swift`, `Sources/TUIView/State/PropertyWalk+Objects.swift`;
  `Documentation/Historical/State and dynamic properties/Finding dynamic properties, and writing back what update() changes.md`.

### State keys in dynamic properties

- **Asks:** what SwiftUI does with the `@State` inside an enum view's cases, an enum property's cases and a
  multi-value payload, and (under `-D OPTCONF`) an optional property going `nil` and back. Each case prints what
  the body reads, after pokes through the `$state` bindings the bodies hand out.
- **Files:** `skey.swift`, `skey.out`, `skey-optconf.out`.
- **Ran:** macOS 15, SwiftUI 6.5.4, 2026-10-11.
- **Was:** `SKEY/probe/`.
- **Cited by:** `Sources/TUIView/State/NestedPropertyBinding.swift`, `Sources/TUIView/State/StateStorage.swift`;
  `Tests/TUIFoundationTests/DynamicPropertyStateKeyTests.swift`;
  `Documentation/Historical/State and dynamic properties/Finding dynamic properties, and writing back what update() changes.md`.

### Alignment guides

- **Asks:** whether an explicit alignment guide's value is used as given or clamped to the view's own size, in
  `VStack` and `HStack` for every alignment (`guide.swift`, `guide.out`); then the same question for `ZStack`,
  `LazyVStack`, a single child's `.frame` and `.overlay` placement, a stack inside a frame, and a stack whose
  region a flexible child sets (`guide2.swift` to `guide6.swift`, each with its `.out`; all share
  `guide.swift`'s harness).
- **Also:** `GuideProbeTests.swift`, a Swift Testing suite that records TUI's placements for the same matrix
  into `tuikit.out` (copy it into `Tests/TUIIntegrationTests` to run it; it was written against TUI at 45e9a1f7a and
  has not been re-checked against today's); `check.py`, which fits SwiftUI's rule and TUI's then rule to the
  two outputs (`python3 check.py`: 135 rows each, no mismatch) and says which of TUI's two rules made each of
  the 72 differing rows differ. `tuikit.out` records TUI before the fix this probe led to.
- **Also:** `layout1.swift` (`layout1.out`): which guides leave which containers by kind — an edge or centre
  guide out of statically-one-view stacks, stack layouts, branches, loops, `AnyView`, a custom layout and a
  `Grid`; text baselines and custom guides out of rows, layers and layouts (case `A`, `C`) — and a guide through
  `.frame`, `.border`, `.offset`, `.overlay`, `.background`, `.padding`, `.fixedSize`, `.position` (case `B`);
  `EmptyView` under a frame, padding, overlay, background, border, `.id`, `.onAppear` and a `Group`, and a frame
  with an ideal and no maximum offered nothing (case `D`).
  Run on macOS 15.8.1, SwiftUI 6.5.4, Swift 6.2.4, 2026-10-18 (lane LAYOUT).
- **Also:** `badge.swift` (`badge.out`): a custom guide set on a view passes `.badge(_:)` (a count and a string)
  and `.textCase(_:)` as it passes no modifier at all. Run on macOS 15.8.1 with Xcode's `swiftc`, 2026-10-19 (the
  review of lane LAYOUT).
- **Ran:** macOS 15.8.1, SwiftUI 6.5.4, Swift 6.2.4, 2026-10-11.
- **Was:** `GUIDE/probe/` and `GUIDE/probe2/` (and `GUIDE/tuikit.out`); `layout1.swift` was `LAYOUT/probe/l1.swift`.
- **Cited by:** `Tests/TUIChromeTests/AlignmentGuideParityTests.swift`,
  `Tests/TUIChromeTests/AlignmentGuideContainerParityTests.swift`,
  `Tests/TUIFoundationTests/AlignmentGuideKindTests.swift`,
  `Tests/TUIFoundationTests/AlignmentGuideWrapperTests.swift`,
  `Tests/TUIFoundationTests/EmptyContentLayoutTests.swift`;
  `Sources/TUIView/Core/PrimitiveViews.swift`, `Sources/TUIFoundation/Modifiers/OverlayModifier.swift`,
  `Sources/TUIView/Rendering/StaticViewListCount.swift`;
  `Documentation/Historical/Layout and geometry/README.md`.

### List pinned headers and row stripes

- **Asks:** which macOS `List` styles float (pin) their section headers, and what separator style their table view
  uses (`pin.swift`); which rows a `Table` of each style and a `List`, sectioned or not, tint with alternating
  backgrounds, sampling each row's background pixel (`phase.swift`, built with `common.swift`).
- **Ran:** macOS 15.8, 2026-10-06 and 2026-10-07. Neither output was kept; the results are in the D6L decisions.
- **Was:** `D6L/probe/` (`phase.swift` and `common.swift` in `D6L/probe/phase/`).
- **Cited by:** `Sources/TUILists/Views/_ListCore.swift`, `Sources/TUITables/Views/Table.swift`;
  `Documentation/Historical/Lists, tables and tabs/Stripes, surfaces and separators.md`.

### Sections and subview counting

- **Asks:** how SwiftUI counts the subviews of a `ForEach` row that is a `Group`, a tuple, an `AnyView`, a
  `Section` or an `if` (`b15.swift`); how a `Section` with a header and a footer lays out in stacks, lazy stacks,
  a `ZStack` and a `Grid`, and collapsed (`b16.swift`); how `Spacer`s and alignment guides behave when a container
  proxies its subviews (`b17.swift`); how a tag and a `ForEach` in a body come through `ForEach(subviews:)` and
  `Group(subviews:)` (`cv.swift`); layout values and guides read by a `Layout` (`lv.swift`); whether `zIndex`
  survives `ForEach(subviews:)` in a `ZStack`, from the pixels (`z.swift`). Then, a second round: a view of the
  app's own whose body is several views, beside others in a container, in a loop or behind an `if`
  (`composite.swift`); a `Section` in a `Form` of each style, collapsed and expanded (`form.swift`), and inside a
  view of the app's own (`formcomposite.swift`); deleting the second view of an element's multi-view `List` row
  (`listdel.swift`); and a `Section` in a menu, read from the `NSMenu` of a `CommandMenu` (`menuapp.swift`;
  `menu.swift` tried a `Menu` in a window first, and its pop-up had no items offscreen). All are built with
  `common.swift`, whose `Counter` layout and `probe(_:)` modifier print what a container saw. A third round,
  built alone: a body that is an `if`/`else` of several views, a modifier or an effect on a `Group` of several,
  or an `AnyView`, and a modifier on such a view from outside, in an `HStack`, with how often the effect fires
  (`composite-bodies.swift`).
- **Ran:** macOS 15.8, 2026-10-04 and 2026-10-05; `composite-bodies.swift` macOS 15.8.1, 2026-10-19. `cv.swift`,
  `lv.swift` and `z.swift` kept no output.
- **Was:** `D1S/probe/`, and `D1S/probe2/` for the second round.
- **Cited by:** `Sources/TUIView/Core/AnyViewMembers.swift`, `Sources/TUIView/Rendering/CompositeMembers.swift`,
  `Sources/TUIForms/Views/FormContentExtraction.swift`, `Sources/TUIFoundation/Rendering/MenuSections.swift`,
  `Sources/TUILists/Views/ListRowEditOwner.swift`; `Tests/TUIListsTests/AnyViewMembersTests.swift`,
  `Tests/TUIFoundationTests/SubviewLayoutTraitsTests.swift`, `Tests/TUIListsTests/ForEachRowMembersTests.swift`,
  `Tests/TUIListsTests/ForEachRowVaryingMembersTests.swift`,
  `Tests/TUIIntegrationTests/SectionPartsTests.swift`, `Tests/TUIListsTests/CompositeMembersTests.swift`,
  `Tests/TUIListsTests/ListMultiViewRowEditingTests.swift`,
  `Tests/TUIFormsTests/FormWrappedSectionTests.swift`, `Tests/TUIMenusTests/MenuSectionTests.swift`;
  `Documentation/Historical/Layout and geometry/README.md`.

### Pinned section headers and footers

- **Asks:** where SwiftUI pins section headers and footers, read from the pixels down a column (`scan.swift`
  classifies them) as each probe scrolls through an `NSScrollView`: a vertical `LazyVStack` (`p1.swift`); the
  footer clamp, grids, horizontal stacks, `List`s, `scrollTo` under a pinned header, a section inside a row, a
  modified section (`p2.swift`); grid columns and `List` header geometry (`p3.swift`); grids in a fixed frame
  (`p4.swift`); where a grid puts a narrow header and footer and the spacing around them (`p5.swift`); and
  `PinnedScrollableViews`' raw values (`raw.swift`). The `p` probes are built with `common.swift` and
  `scan.swift`.
- **Ran:** macOS 15.8, 2026-10-03.
- **Was:** `w10b/probe/`.
- **Cited by:** `Tests/TUIIntegrationTests/PinnedRowSectionTests.swift`,
  `Tests/TUIGridTests/LazyGridSectionTests.swift`; wave 10b's entries in
  `Documentation/Historical/` (found by id through its `Index of decision ids.md`).
### Swift runtime layouts

- **Asks:** not SwiftUI but the Swift runtime: the layouts the planned property walk reads, each checked before
  the walk relied on it. A field record's ownership, from the suffix of its mangled type name, and where a class's
  metadata keeps its descriptor (`own.swift`); calling an enum's value witnesses from its metadata, for a user
  enum, a generic one instantiated at run time and `Optional` (`vwt.swift`); an existential type's flags and how a
  `nil` optional of one looks (`exflags.swift`); what an `unowned` reference holds for a native object, an
  Objective-C one and a tagged pointer, alive and gone (`unex.swift`); loading `weak` and `unowned` references in
  place, held as `AnyObject` (`typedref.swift`); and whether the runtime's box entry points are names the
  compiler reserves (`pb.swift`). No views; none of those kept its output, and the results are in the citing
  comments and the DYNVFIX decisions. And one cost, timed: what each way of noting when a `@State` was made adds
  to making one — a task local read, a clock, a global — over a backing and its box made in a loop, best of five
  runs of two million (`stamp.swift`, built `-O`; `stamp.out`, two runs).
- **Ran:** macOS 15.8, arm64 only (x86_64 is unmeasured), Xcode's Swift 6.2.4, 2026-10-12.
- **Was:** `DYNVFIX/probe/`; `stamp.swift` `DYNVCLAIM/swiftui-first/`.
- **Cited by:** `Sources/TUIView/Rendering/FieldDescriptors.swift`, `Sources/TUIView/State/EnumPayloads.swift`,
  `Sources/TUIView/State/DynamicTypes.swift`, `Sources/TUIView/State/State.swift` (`stamp.out`);
  `Documentation/Historical/State and dynamic properties/Finding dynamic properties, and writing back what update() changes.md`.

### Localization keys

- **Asks:** what key SwiftUI's `LocalizedStringKey` records for each kind of interpolated value — every integer
  and floating-point width, `CGFloat`, `String`, `Text`, `Image`, `AttributedString`, a date style, format styles,
  `specifier:`, `NSNumber` with and without a formatter, a `ReferenceConvertible`, a date range, and a literal `%`
  beside a number — read from the key's stored `key` field (`keys.swift`, `keys.out`). No view is drawn.
- **Ran:** macOS 15.8, SwiftUI 6.5.4, Xcode's Swift 6.2.4, 2026-10-13.
- **Was:** `T10/probe/`.
- **Cited by:** `Sources/TUIFoundation/Localization/LocalizedStringKey.swift`;
  `Tests/TUIPresentationTests/SwiftUIKeySpellingTests.swift`; `Sources/TUI/TUI.docc/Articles/Localization.md`;
  `Documentation/SwiftUI parity/SwiftUI compatibility guide.md`.

### Layout priority

- **Asks:** how SwiftUI's `HStack` and `VStack` give space by `layoutPriority(_:)`: two ten-character `Text`s in
  a row too narrow for both, with no priority, with one on either, with three levels, with a negative one, and
  two of one priority beside a third; a flexible frame with a priority beside a `Spacer` and beside a `Text`; a
  fixed frame wider than the row; which modifiers written after the priority keep it (`.foregroundStyle`,
  `.font`, `.opacity`, `.background`, `.id`, `.tag`, a `Group`) and which lose it (`.padding(0)`, `.frame`); and
  a column of two multi-line `Text`s (`priority.swift`, `priority.out`). Each child's width is read with a
  `GeometryReader` in its background, in characters of a monospaced font.
- **Ran:** macOS 15.8, SwiftUI 6.5.4, Xcode's Swift 6.2.4, 2026-10-13.
- **Was:** `L12/probe/`.
- **Cited by:** `Sources/TUIFoundation/Views/LayoutValueKey.swift`, `Sources/TUIView/Core/BufferModifier.swift`,
  `Sources/TUIFoundation/Views/StackGuidePropagation.swift`,
  `Sources/TUIFoundation/Rendering/LinearSpaceDistribution.swift`; `Tests/TUIFoundationTests/LayoutPriorityTests.swift`;
  `Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md` (L14),
  `Documentation/SwiftUI parity/SwiftUI compatibility guide.md`.

### Animation curves, springs and keyframes

- **Asks:** what SwiftUI's animation types compute, with no view: whether each transition has motion
  (`p1.swift`); how an `Animation` describes and mirrors itself (`p2.swift`); each `UnitCurve`'s values and
  velocities (`p3.swift`); a `Spring`'s parameters, values and velocities by each way of making one (`p4.swift`,
  `p5.swift`); a `KeyframeTimeline`'s values over time (`p6.swift`, `p7.swift`); and the environment's default
  `contentTransition` and how `ContentTransition`s compare (`p8.swift`). Each is a program alone (`@main`, no
  shared file); the numbers print to six places. `p9.swift` is the exception: it hosts a `PhaseAnimator` and a
  `KeyframeAnimator` off-screen and records, through their closures, which phase or value each is handed as
  their triggers change — a trigger runs a phase animator through every phase, not one step, and keyframes
  replay from the initial value, both against SwiftUI's documentation. `p10.swift` hosts one too, and times
  an animated value: a delay written before `repeatForever` comes before every pass, and one written after
  `speed(_:)` is not scaled by it (the semantic audit's item 4). `p11.swift` prints the value every 0.05 s
  for the orders `p10` left open: an autoreversing repeat's wait holds where each pass starts, a delay after a
  repeat comes once, a delay after a speed repeats unscaled, and a repeat of a repeat is erratic.
- **Ran:** against the macOS 26.2 SDK, on the development Mac, 2026-10-03; `p9` and `p10` on 2026-10-14 (macOS 15.8,
  Xcode's Swift 6.2.4, three runs alike); `p11` on 2026-10-18 (macOS 15.8, Xcode's Swift 6.2.4; a frame's
  timing moves a value in the second decimal from run to run, so compare its shape, not with `diff`). `p1`, `p2`, `p3` and `p8` kept no output; their results are in wave
  12's decisions. `p9.out` prints the timing-dependent cases classified (start, end or between), so a rerun
  compares with `diff`.
- **Was:** `w12/probe/`.
- **Cited by:** `Sources/TUIView/Animation/KeyframeCurve.swift`, `Sources/TUICore/Animation/Animation.swift`;
  `Tests/TUICoreTests/AnimationTimingTests.swift`, `Tests/TUIFoundationTests/KeyframeTimelineTests.swift`,
  `Tests/TUIFoundationTests/SpringTests.swift`, `Tests/TUIFoundationTests/UnitCurveTests.swift`; wave 12's entries in
  `Documentation/Historical/` (found by id through its `Index of decision ids.md`).

### Transactions of observed changes

- **Asks:** which transaction SwiftUI updates a body under when one turn of the run loop writes two `@Observable`
  properties the body reads, one plainly and one inside `withAnimation`, in either order; and what an unanimated
  write followed by a `withAnimation` that writes nothing the body read (or nothing at all) is drawn under
  (`txn.swift`, a program of top-level code; `txn.out`). The body records, through `.transaction(_:)`, whether
  each update it was given carried an animation: SwiftUI updates it once per write, the animated write's update
  animated in both orders, and an empty `withAnimation` animates nothing.
- **Ran:** macOS 15.8.1, Xcode's Swift 6.2.4, 2026-10-18, in an `NSHostingView` with no window.
- **Was:** `APPSTATE/probe/`.
- **Cited by:** `Sources/TUIView/State/State.swift` (`AppState.transactionScopeEnded(_:)`);
  `Tests/TUIIntegrationTests/ObservedChangeTransactionTests.swift`;
  `Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md` (A7);
  `Documentation/Historical/State and dynamic properties/Per-app render state: no singletons.md` (B-APPSTATE-2).

### Scroll anchoring

- **Asks:** what a scroll view does with no scroll position bound when the content above the row at its top
  changes (`hold.swift`): rows inserted above, rows removed above, a row above growing, rows inserted below or
  inside the viewport, the top row itself removed, every row replaced — in a `LazyVStack`, an eager `VStack` and a
  `List`, scrolled to row 10, part way into it, or at the top, with no `defaultScrollAnchor` and with each of
  `.top`, `.bottom` and `.center`, unlabelled and for `.sizeChanges`; each change made plainly and again under
  `Transaction.scrollContentOffsetAdjustmentBehavior = .disabled`. It prints the clip view's origin before and
  after, and the row at the viewport's top: for a stack computed from the origin, its rows being 20 points tall
  (so after a row above grows it names the row the grown layout would put there — a lazy stack lays out no row
  off screen, so that case says only that the origin did not move), for a `List` read from its `NSTableView`.
  Top-level code, built alone. `reorder.swift`, the same harness, asks what a reorder does to the row at the top:
  every row reversed, the top row moved to the end, swapped with the next, a row from below the screen moved to
  the start, rows from above moved to the end. `beside.swift`, the same harness again, asks what a change to the
  top row itself or to the rows beside it does: its id changed in place, alone and with five rows inserted above
  it, and with five inserted above, a row inserted just after it, or the row after it or before it removed.
- **Ran:** macOS 15.8, a 300×200 window, 2026-10-12 (`reorder.swift` 2026-10-13, `beside.swift` 2026-10-13).
- **Was:** `SCROLLANCHOR/probe/hold/` (`reorder.swift` as `hold3.swift`); `beside.swift` in
  `SCROLLANCHOR/probe/beside/`.
- **Cited by:** `Sources/TUIFoundation/Views/ScrollWindowHold.swift`,
  `Sources/TUIFoundation/Views/StackTopRowHold.swift`, `Sources/TUILists/Focus/ItemListHandler+Anchor.swift`,
  `Tests/TUITablesTests/ScrollWindowHoldTests.swift`; `Documentation/Layout and scrolling/Scroll
  anchoring.md` §5; `Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md` (R13, R14);
  `Documentation/Historical/Scrolling/README.md`.

### Scroll transitions

- **Asks:** the threshold SwiftUI's scroll transition configurations start with when none is set
  (`stmirror.swift`, `stmirror.out`): the configuration keeps it as data, so a `dump` reads it — `.visible` (1.0)
  for `.interactive` and `.interactive(timingCurve:)`, `.visible(0.5)` for `.animated` and `.animated(_:)`, kept
  by `animation(_:)`. `stanim.swift` (`stanim.out`) drives each default through a scroll view beside the two
  explicit thresholds, at four offsets, and finds it calling its closure exactly as the threshold it holds does.
  Both are top-level code, built alone.
- **Ran:** macOS 15.8.1, Xcode's Swift 6.2.4, 2026-10-19.
- **Was:** `SCROLL/probe/`.
- **Cited by:** `Sources/TUIEffects/Geometry/ScrollTransitionConfiguration.swift`;
  `Documentation/Historical/Layout and geometry/README.md` (B-D5G-8);
  `Documentation/SwiftUI parity/SwiftUI compatibility guide.md`.

### Scroll target behaviours

- **Asks:** what a scroll target behaviour is handed, and where `.paging` and `.viewAligned` land, under
  `.contentMargins` (`margins.swift`, `margins.out`): a behaviour of the probe's own wraps the built-in one and
  logs each call's container, content and proposed target and what the built-in behaviour returned; a resize of
  the window from 100 to 110 points is what makes SwiftUI consult it. Rows 20 points tall in a vertical scroll
  view, under top and bottom margins, from several offsets. The container is the bounds less the margins, the
  content its size without them, and the target the area inside the margins at the offset, the content's first
  row at 0; `.viewAligned` lands a row at the top margin. `.paging`'s page is the container only without a top
  margin: with one it is the container plus HALF the top margin (`margins2.swift`, `margins2.out`, margins of
  several sizes, the page read off the lattice the stops fall on). `hmargins.swift` (`hmargins.out`) is the
  horizontal case, a carousel of 60-point cards under leading and trailing margins: the same, with the leading
  margin in the top's place. All three are top-level code, built alone.
- **Ran:** macOS 15.8.1, Xcode's Swift 6.2.4, 2026-10-19.
- **Was:** `SCROLL/probe/`.
- **Cited by:** `Sources/TUIFoundation/Focus/ScrollViewHandler+Targeting.swift`,
  `Sources/TUIFoundation/Views/ScrollTargetBehaviors.swift`; `Tests/TUIAppTests/ScrollTargetViewAlignedTests.swift`,
  `Tests/TUIIntegrationTests/ScrollTargetBehaviorTests.swift`;
  `Documentation/Historical/Scrolling/README.md` (B-D2S-7),
  `Documentation/Historical/Scrolling/README.md` (B-SCROLL-1),
  `Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md` (R15).

### Scroll to a row

- **Asks:** what `ScrollViewProxy.scrollTo(_:anchor:)` does with a row of a vertical stack inside a purely
  horizontal `ScrollView`, which cannot scroll to it down (`hrow.swift`, `hrow.out`): rows of five widths, the stack
  centred and leading, the request naming one row with no anchor and with `.leading`, `.trailing` and `.center`.
  It seeks along x: the row's own span is aligned by the anchor's `x` (row 4, the widest, to 300 under
  `.trailing` and 150 under `.center` in a 200-point view; a centred narrower row to its own edge), and no anchor
  moves nothing where the row already shows. Top-level code, built alone.
- **Ran:** macOS 15.8.1, Xcode's Swift 6.2.4, 2026-10-19.
- **Was:** `SCROLL/probe/`.
- **Cited by:** `Documentation/Historical/Scrolling/README.md` (C-SCROLL-1);
  `Documentation/SwiftUI parity/SwiftUI compatibility guide.md`.

### Nested scroll position

- **Asks:** what a `.scrollPosition(id:)` bound to an outer `ScrollView` does to a `ScrollView` or a `List` nested
  in its content (`nested.swift`, `nested.out`): thirty 20-point rows, then the nested scrollable 60 points tall,
  its ids apart from the outer's, shared with them, or past them. An id the app writes is sought by the outer view
  where its content holds it, and the nested one stays put; an id only the nested one holds is sought there, by the
  least move, and the outer view does not move to show it. A user's scroll of the outer view writes its row back,
  and the nested one does not follow; a scroll of the nested one writes nothing. A user's scroll is posted as
  AppKit reports one, the live-scroll notifications around a move of the clip view: a bare move writes nothing
  back, even on the outer view. Top-level code, built alone.
- **Ran:** macOS 15.8.1, Xcode's Swift 6.2.4, 2026-10-19.
- **Cited by:** `Sources/TUIFoundation/Views/ScrollView+Content.swift`;
  `Tests/TUITablesTests/ListScrollPositionTests.swift`;
  `Documentation/Historical/Scrolling/README.md` (B-SCROLL-6);
  `Documentation/SwiftUI parity/SwiftUI compatibility guide.md`.

### Ragged text in a larger frame

- **Asks:** where SwiftUI draws the lines of a multi-line `Text` whose lines differ in width ("aaaa" over "bb")
  in a frame larger than the `Text`, wider or taller, under each frame alignment and each `multilineTextAlignment`:
  each line placed by the frame on its own width, or the `Text` placed as one block, its lines aligned inside it
  (`ragged.swift`, `ragged.out`). A program of top-level code; monospaced, so one character's advance stands in
  for a cell, and each line's ink is found in the pixels drawn. The block, in every case: in a 10-wide centred
  frame both lines start 3 characters in.
- **Ran:** macOS 15.8.1, SwiftUI 6.5.4, Xcode's Swift 6.2.4, 2026-10-13.
- **Was:** written for lane BUGS13 (`BUGS13/probe/`).
- **Cited by:** `Sources/TUIFoundation/Modifiers/FrameModifier.swift`; `Tests/TUIIntegrationTests/PlacementOverflowTests.swift`;
  `Documentation/SwiftUI parity/SwiftUI compatibility guide.md`.

### Trailing values and labels

- **Asks:** where SwiftUI draws the lines of a value or a label of several lines that `LabeledContent` and `Form`
  put at a trailing edge: each line flush with that edge, or the lines leading inside a block placed there (as a
  frame's alignment alone places them, "Ragged text in a larger frame" above). `LabeledContent` alone, in a grouped
  `Form` and in a columns `Form`, with a value of two lines ("short" over "a much longer line") and one that wraps,
  and a columns `Form` whose label is two lines ("a" over "longer label") beside a longer one (`trailing.swift`,
  `trailing.out`). A program of top-level code, after the ragged probe; the value is drawn black and the label red,
  so that the two can share a row. The grouped form's value ends every line at the trailing edge, its wrapped lines
  too; the columns form's label column places the two-line label as a block at its trailing edge, "a" at the start
  of "longer label"; alone, and in a columns form, the value leads.
- **Ran:** macOS 15.8.1, SwiftUI 6.5.4, Xcode's Swift 6.2.4, 2026-10-13.
- **Was:** written for lane BUGS13's review fixes (`BUGS13/probe/`).
- **Cited by:** `Sources/TUIForms/Styles/LabeledContentStyle.swift`; `Tests/TUIIntegrationTests/LabeledContentTests.swift`,
  `Tests/TUIIntegrationTests/FormTests.swift`; `Documentation/SwiftUI parity/SwiftUI compatibility guide.md`.

### Stack spacing per pair

- **Asks:** what `ViewSpacing`'s own values answer `distance(to:along:)` with — `ViewSpacing()` and `.zero` against
  each other, and `.zero` merged with `ViewSpacing()` — and what `LayoutSubview.spacing` holds for boxes, texts,
  colours, buttons, a spacer, a padded box, a nested `HStack`, and layouts that state `.zero`, `ViewSpacing()` or
  keep `Layout`'s default (`distances.swift`); and what a stack's `spacing: nil` puts between two views that state
  their own preferences (`spacing.swift`): layouts that ask for no space on all, the leading or the trailing edge,
  beside each other and beside plain boxes; through `EmptyView`, a `Spacer`, `.padding(0)`, `.padding(4)`, `.id`,
  `.foregroundStyle`, `.frame` (fitting, wider, height-only, and a leading `maxWidth`), `.border`, `.background`,
  `.offset`, `.position`, `AnyView`, a view of the app's own, `AnyLayout`,
  `ForEach`, `Group`, an `if` and a nested `HStack`; in `HStack`, `HStackLayout`, `LazyHStack` and `VStack`; and
  with `spacing:` stated. Built alone, each with `-parse-as-library`. `nested.swift` (`nested.out`, lane LAYOUT,
  2026-10-18): which edges a nested `HStack`, `VStack`, `ZStack` and lazy stack state, and a view of the app's own
  whose body is a stack, an `if`/`else` or a padding.
- **Ran:** macOS 15.8.1, Xcode's Swift 6.2.4, 2026-10-13 (the wider frames, `.position` and `AnyView` rows in the
  review of B20, the same day); `nested.swift` 2026-10-18.
- **Was:** `BITEMS1/probe/`; `nested.swift` was `LAYOUT/probe/sp1.swift`.
- **Cited by:** `Sources/TUIFoundation/Views/ViewSpacing.swift`, `Sources/TUIFoundation/Views/Layout.swift`,
  `Sources/TUIFoundation/Views/StackSpacingPreference.swift`, `Sources/TUIView/Rendering/ChildInfo.swift`;
  `Tests/TUIGridTests/ViewSpacingTests.swift`, `Tests/TUIGridTests/StackSpacingPerPairTests.swift`;
  `Documentation/SwiftUI parity/SwiftUI compatibility guide.md` (the Layout row); B20 in
  `Documentation/Historical/Layout and geometry/Stack spacing, and what a container counts as its children.md`;
  `Documentation/Historical/Layout and geometry/Stack spacing, and what a container counts as its children.md`.

### Flexible frames

- **Asks:** how SwiftUI's flexible frame, `.frame(minWidth:idealWidth:maxWidth:…)`, sizes itself and what it
  offers its content: a five- and a 37-character `Text`, a `Color.clear` and a `Text` made rigid by `.fixedSize()`,
  under an ideal alone, a finite maximum alone, a minimum alone, each pair, `.infinity`, and an ideal above the
  maximum; offered 80 and 20 characters by a fixed outer frame, and offered nothing by `.fixedSize()`; and the
  same for heights, offered 10 and 2 lines and nothing (`frame.swift`, `frame.out`). A program of top-level code,
  after the layout-priority probe; each size is read with a `GeometryReader`, in characters and lines of a
  monospaced font. A maximum fills the offer up to it; an ideal is read only when nothing was offered, and is then
  the frame's size; an ideal above the maximum wins.
- **Ran:** macOS 15.8.1, SwiftUI 6.5.4, Xcode's Swift 6.2.4, 2026-10-15.
- **Was:** written here.
- **Cited by:** `Sources/TUIFoundation/Modifiers/FlexibleFrameAxis.swift`;
  `Tests/TUIFoundationTests/FlexibleFrameSwiftUIRuleTests.swift`;
  `Documentation/SwiftUI parity/SwiftUI compatibility guide.md` (§2.1),
  `Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md` (U1).

### Matched geometry

- **Asks:** where SwiftUI DRAWS the views a `matchedGeometryEffect` links, read from the layer tree's
  presentation frames (each view a coloured layer) rather than from a `GeometryReader`, which reports where a
  view is laid out. `mg1.swift`: a follower (`isSource: false`) of a larger source under each property set and
  anchor, with a line below it to show the size it takes in its parent's layout; a follower before its source,
  two sources, a follower in an `HStack`. `mg2.swift`: the same with a follower content that takes the size it
  is offered, and with each pair of follower and source anchors. `mg2b.swift`: a content of fixed size, for
  the formula SwiftUI places it by. `mg3.swift`: under a 4 s linear animation, sampled every 0.5 s — a view
  inserted as another of its id is removed (`if`/`else`, and two `if`s, the inserted view's laid-out size
  logged at each change), a follower whose id changes, a source its layout moves, and two plain insertions.
  Each is a program alone (`@main`, built with `-parse-as-library`); `mg2`–`mg3` copy `mg1`'s harness.
  Found: a follower keeps its own place in the layout and is drawn with its anchor on the point the source's
  anchor names, at the source's size; matching the size alone it stays at its own corner; a fixed content is
  offset from the matched frame by twice its anchor's share of the difference; an inserted view is carried
  from the removed one's frame and laid out at every size between, and a follower whose id changes is scaled
  there instead.
- **Ran:** macOS 15.8, Xcode 26's SDK and Swift 6.2.4, 2026-10-18. `mg1`, `mg2` and `mg2b` print the same on a
  rerun (`diff` their `.out`); `mg3`'s samples move by a point or two with the frame's timing.
- **Was:** `O4/probe/`.
- **Cited by:** `Sources/TUIEffects/Geometry/MatchedGeometryEffect.swift`;
  `Tests/TUIEffectsTests/MatchedGeometryEffectTests.swift`; `Documentation/SwiftUI parity/Deliberate
  deviations from SwiftUI.md` (A8), `Documentation/SwiftUI parity/SwiftUI compatibility guide.md` (the
  Animation row); `Documentation/Historical/Shapes, effects and animation/Matched geometry and the zoom transition.md`.

### Shadowed shape styles

- **Asks:** what `ShapeStyle.shadow(_:)` casts, read back as pixels from an `ImageRenderer` at scale 1 (a
  100 × 100 frame round a 40 × 40 view, `(30, 30)`–`(70, 70)`). `shadowstyle.swift`: which style the static
  `.shadow(_:)` takes in a `.background(_:)` and in a `.backgroundStyle(_:)` (Q1, Q2); `.secondary` and
  `.foreground` under a shadowed foreground style (Q4); a fade before and after the shadow (Q5); whether a
  background's inner shadow is over the content in front of it (Q9); a text's letters, a stroke, a background
  and a border casting (Q10–Q13). `stacked.swift`: two shadows on one style, each kind first (Q6), a
  translucent shadow colour (Q14) and a ramp fading along its length (Q15). Each is a program alone (`@main`,
  built with `-parse-as-library`).
  Found: the static form's style is the foreground, and the background style inside `backgroundStyle(_:)`;
  `.secondary` keeps the shadow at half; a fade on either side of the shadow halves it; an inner shadow in a
  background darkens the fill and not the content in front of it; two shadows are each cast from the style's
  drawing, not one from the other; a ramp's shadow follows its alpha pixel by pixel.
- **Ran:** macOS 15.8, Xcode 26's SDK and Swift 6.2.4, 2026-10-19; both print the same on a rerun.
- **Was:** `W1B/probe/` (`stacked.swift` as `q6.swift`).
- **Cited by:** `Sources/TUIFoundation/Styling/ShapeStyle+Shadow.swift`,
  `Tests/TUIIntegrationTests/ShapeStyleShadowTests.swift`; `Documentation/Historical/Shapes, effects and
  animation/Shadows.md` (B-W1B-1).

### Image paint

- **Asks:** how `ImagePaint` repeats an image, read back as pixels from an `ImageRenderer` at scale 1:
  `imagepaint.swift` fills 16 × 16 shapes, and a background and a text's letters, with a 4 × 4 picture of four
  coloured quarters, at scales 1, 2 and 0.5, from an image of scale 2, from two source rectangles, in a
  13 × 13 shape centred in a larger frame, and moved by `ShapeStyle.in(_:)`, and prints a row of pixels from
  each as letters. A program alone (`@main`, built with `-parse-as-library`).
  Found: the tile is the source rectangle's share of the image's size in points, times the scale, repeated
  from the top-leading corner of the frame filled (a shape's, a background's, a text's); `in(_:)` moves where
  the tiles start to its rectangle's origin, and its size changes nothing.
- **Ran:** macOS 15.8, Xcode 26's SDK and Swift 6.2.4, 2026-10-19; prints the same on a rerun.
- **Was:** `W1B/probe/`.
- **Cited by:** `Sources/TUIFoundation/Styling/ImagePaint.swift`, `Sources/TUIFoundation/Styling/ShapeStyle.swift`
  (`in(_:)`), `Tests/TUIBitmapsTests/ImagePaintTests.swift`;
  `Documentation/Historical/Shapes, effects and animation/Shapes.md` (B-W1B-4).

### Transitions

- **Asks:** how SwiftUI plays a view's arrival and removal, read from the layer tree's presentation frames as
  `Matched geometry/mg3.swift` reads them (each view a coloured layer, sampled every 0.5 s under a linear
  animation; a layer's opacity is multiplied down its ancestors). `tr1.swift`: with no `.transition` written,
  an `if`/`else` whose branch flips in a column, a `switch`, a `ForEach` row inserted and removed, and a view
  whose whole body is an `if`/`else`; an `asymmetric` transition whose halves have animations of their own; a
  transition's `.animation(nil)` under `withAnimation`; a transition's own animation with no `withAnimation`;
  and a custom transition that collapses its height. `tr2.swift`: how a transition's own animations compose —
  an outer `.animation` over halves with their own, two `.animation` calls, `nil` before and after an
  animation, and parts of a `combined` transition with different ones. `tr3.swift`: whether a fade reaches
  what a view draws displaced by `.offset`, with no transition and with `.opacity`. `tr4.swift`: what
  `.blurReplace` draws besides the blur — how far it scales, about which point, and whether it fades — in
  `.downUp` and `.upUp`, sampled every 0.25 s under a 2 s animation. Each is a program alone
  (`@main`, built with `-parse-as-library`); `tr2`, `tr3` and `tr4` copy `tr1`'s harness.
  Found: with no transition the leaving view fades out where it was, drawn beneath its siblings, while the new
  one fades in and the views below glide — a branch flip, a `switch` case and a `ForEach` row alike, and a
  whole body's two branches overlap at its origin; each half of an `asymmetric` transition keeps its own
  animation, and a half with none takes the change's; the animation nearest the view wins, `nil` included,
  which plays the transition at once under any `withAnimation`; a transition's own animation plays with no
  `withAnimation`; each part of a `combined` transition runs under its own; a collapsing transition's
  neighbours move continuously as its frame shrinks; a view drawn displaced fades with the view it belongs to;
  `.blurReplace` scales about the centre between 0.9 and 1 (`.upUp` leaves to 1.1) and fades between 0 and 1.
- **Ran:** macOS 15.8, Xcode 26's SDK and Swift 6.2.4, 2026-10-19 (`tr4`: 2026-10-24). Samples move by a point or two, and an
  opacity by a hundredth, with the frame's timing.
- **Was:** `TRANSITIONS2/probe/`.
- **Cited by:** `Sources/TUIEffects/Animation/AnyTransition.swift`,
  `Sources/TUIEffects/Animation/TransitionModifier.swift`, `Sources/TUIEffects/Animation/TransitionEffects.swift`,
  `Sources/TUIView/Animation/DefaultTransition.swift`, `Sources/TUIView/Animation/ChildFade.swift`,
  `Sources/TUIView/Animation/BranchTransition.swift`; `Tests/TUIEffectsTests/TransitionTests.swift`,
  `Tests/TUIEffectsTests/TransitionAnimationTests.swift`, `Tests/TUIEffectsTests/BranchAndRowFadeTests.swift`,
  `Tests/TUIEffectsTests/DefaultTransitionTests.swift`; `Documentation/SwiftUI parity/Deliberate deviations
  from SwiftUI.md` (A3, A6), `Documentation/SwiftUI parity/SwiftUI compatibility guide.md` (the Animation row);
  `Documentation/Historical/Shapes, effects and animation/Inserting and removing views: transitions and the default fade.md`,
  `Documentation/Historical/Shapes, effects and animation/Matched geometry and the zoom transition.md` (B-O4-2),
  `Documentation/Historical/Shapes, effects and animation/Inserting and removing views: transitions and the default fade.md` (A34);
  `Sources/TUIEffects/Animation/BuiltInTransitions.swift`, `Tests/TUIEffectsTests/BlurReplaceTransitionTests.swift`.

### Badge prominence

- **Asks:** where a `.badgeProminence(_:)` written on a `List` row reaches that row's badge: around the
  `.badge(_:)`, inside it, around a padding after it, and on the list with a row's own `.standard` around its
  badge; and whether a `.badge(_:)` with a padding after it is still drawn (`badgeprom.swift`, `badgeprom.out`,
  built with `common.swift`). Counts the non-white pixels in each row's trailing 70 points: a `.standard` badge
  sits in a light grey capsule (1128 pixels), a `.decreased` one is bare grey text (157).
- **Ran:** macOS 15.8.1, Xcode's Swift 6.2.4, 2026-10-18.
- **Was:** `LISTS/probe/`.
- **Cited by:** `Sources/TUIFoundation/Modifiers/BadgeModifier.swift`,
  `Tests/TUIListsTests/BadgeProminenceTests.swift`;
  `Documentation/Historical/Lists, tables and tabs/Badges and the prominence of a row.md` (B72),
  `Documentation/Historical/Lists, tables and tabs/Badges and the prominence of a row.md` (B-LISTS-1).

### Hierarchical table insertions

- **Asks:** which loop of a hierarchical `Table` — a `ForEach` of `DisclosureTableRow`s among the roots, or a
  `ForEach` of rows beneath a branch, each with `dropDestination(for:action:)` — hears a drop between rows, and at
  what offset (`outlineinsert.swift`, `outlineinsert.out`, built with `common.swift`). The table is an
  `NSOutlineView`; the probe hands its data source a drop at the `(item, childIndex)` the outline view would
  propose, carrying a string, as `validateDrop` and then `acceptDrop`. A drop among a branch's rows goes to that
  branch's loop at the child index; one among the roots to the roots' loop. Where a branch's rows have no loop
  with a destination, the roots' loop hears it at the child index — a place among the roots unrelated to the drop —
  and where only the branches' loops have one, a drop among the roots is refused. A drop ON a row (child index -1)
  traps inside SwiftUI and is left out.
- **Ran:** macOS 15.8.1, Xcode's Swift 6.2.4, 2026-10-19.
- **Was:** `LISTS2/probe/`.
- **Cited by:** `Sources/TUITables/Views/TableOutline.swift`, `Tests/TUITablesTests/TableRowDragAndDropTests.swift`;
  `Documentation/Historical/Input, keys and gestures/Drag and drop.md` (B80).

### Picker sections

- **Asks:** how a macOS menu `Picker` draws a `Section` among its options: reads back the menu of the
  `NSPopUpButton` SwiftUI makes and prints each item's kind and title (`pickersection.swift`, `pickersection.out`,
  built with `common.swift`). Each section is wrapped in separators, its header an `NSMenuItem` section header
  over its options. A section a condition empties keeps its header between its separators, over no options,
  and the collapsed control is as wide as that header needs (`emptied`: 197 points, against 74 for its one
  option alone, `baseline`).
- **Ran:** macOS 15.8.1, Xcode's Swift 6.2.4, 2026-10-18; the emptied section 2026-10-19.
- **Was:** `LISTS/probe/`.
- **Cited by:** `Sources/TUIPickers/Views/Picker.swift`, `Sources/TUIPickers/Views/_PickerOptionsReader.swift`,
  `Tests/TUIPickersTests/PickerSectionTitleTests.swift`;
  `Documentation/SwiftUI parity/SwiftUI compatibility guide.md` (§1, Pickers).

- **Also asks** (`ideal-placed.swift`, `ideal-placed.out`): a frame with an ideal width and no maximum round a
  5-wide box, under `.fixedSize()`, as each container places it. A row (`HStack`, `HStackLayout`), a stack of one
  view, `.padding`, `.border` and a background's base pass the unspecified width on (the frame is its ideal, 10);
  a column or a `ZStack` of several, `VStackLayout`, `ZStackLayout`, a `Grid` and an overlay's layer offer it a
  width as they place it (its content's, 5). Ran 2026-10-19, macOS 15.8.1, with Xcode's `swiftc`; cited by
  `EnvironmentValues.offeredNoWidth` (`ContainerAxisEnvironment.swift`) and
  `Tests/TUIFoundationTests/FrameIdealOfferedNothingTests.swift`.

### Form rows

- **Asks:** where a `Form`, columns and grouped, puts a row beside a plain `LabeledContent` with a shorter label.
  `modified.swift` (`modified.out`) writes a modifier on a `LabeledContent` row — `.foregroundStyle`, `.disabled`,
  `.font`, `.padding`, `.frame`, `.background`, `.opacity`, `.offset`, `.help`, `.tag`, `.id`, an `HStack` around it
  — and reads where its label and value go: the label stays in the label column for every one, the modifier applying
  to the row. `rows.swift` (`rows.out`) asks the same of the bare labelled controls — `Picker` in each macOS style,
  `Slider`, `Stepper`, `DatePicker`, `ColorPicker`, `Toggle` as a checkbox and as a switch, `TextField`, `Gauge`,
  `ProgressView` — and of more modifiers: padding on a `LabeledContent`, a `Toggle`, a `Picker` and a `Button`, a
  background, help, a tag, an id, `.onAppear`, `.onChange`, `.task`, `.onTapGesture`, `.overlay`, `.border`,
  `.contextMenu`, `.labelsHidden()` and `.keyboardShortcut`. The control's extent is read off the pixels. A picker
  of any style, a slider, a stepper, a date picker, a colour picker, a switch and a text field are field rows: the
  label in the label column, the control in the value column, and in a grouped form the label leading and the
  control trailing (a slider and a segmented picker from 45% of the row). A checkbox is in the value column, its
  label after it. A leading padding on a field row widens the label column by as much; on a checkbox or a button it
  moves the control on from where it would be. A hidden label takes no part in the column. `unlabelled.swift`
  (`unlabelled.out`) asks where a row with no label goes: a `Slider(value:)`, a control or a `LabeledContent` whose
  label is an `EmptyView`, a `Picker("")`. In a columns form each is in the value column, as a `Text` written bare
  is; in a grouped form the control trails the row (a slider from 45% of it), as a labelled one's does.
  `more-modifiers.swift` (`more-modifiers.out`) writes the modifiers `rows.swift` did not try on a `LabeledContent`,
  a `Picker` and a `Button` — `.onKeyPress`, `.transition`, `.zIndex`, `.layoutPriority`, `.focusedValue`,
  `.preference`, `.onGeometryChange`, `.sheet`, `.popover`, `.alert`, `.confirmationDialog`, `.badge` — and each row
  stays in its place, in both styles. `appview.swift` (`appview.out`) writes each control — a `Picker`, a `Toggle` as
  a checkbox and as a switch, a `Slider`, a `Stepper`, a `Button`, a `LabeledContent`, a `TextField` — directly and
  as the whole body of a `struct` of the app's own, and a picker two such views deep and under a modifier: every
  one lays out exactly as written bare, label and row frames and drawn extent alike, in both styles.
- **Ran:** macOS 15.8.1, SwiftUI 6.5.4, Xcode's Swift 6.2.4; `modified.swift` 2026-10-14, `rows.swift` 2026-10-19,
  `unlabelled.swift`, `more-modifiers.swift` and `appview.swift` 2026-10-19.
- **Was:** `PROBES-1014/labeledcontent/` (`p3-modified-rows.swift`) and `FORMS/probes/` (`p4-form-rows.swift`,
  `p5/unlabelled.swift`, `p5/modifiers2.swift`).
- **Cited by:** `Sources/TUIForms/Views/FormContentExtraction.swift`,
  `Sources/TUIForms/Views/Form.swift` (a field row's label column),
  `Sources/TUIFoundation/Views/FormRowRewrapping.swift` and the modifiers' conformances to it (in
  `LifecycleModifier.swift`, `OnChangeModifier.swift`, `GestureModifier.swift`, `KeyboardShortcutModifier.swift`,
  `ContextMenuModifier.swift`, `OverlayModifier.swift`, `FocusPathModifier.swift`, `DragAndDrop+Form.swift`,
  `TransitionModifier.swift`, the presentation modifiers and beside them), `Sources/TUIFoundation/Views/FormControlRow.swift`
  and the labelled controls' conformances (`Sources/TUIPickers/Views/Picker+Form.swift`,
  `Sources/TUINumericControls/Views/NumericControls+Form.swift`, `Sources/TUIColorPicker/Views/ColorPicker.swift`),
  `Tests/TUIIntegrationTests/FormModifiedRowTests.swift`, `Tests/TUIIntegrationTests/FormLabelledControlTests.swift`;
  `Documentation/SwiftUI parity/SwiftUI compatibility guide.md` (Containers, `Form`);
  `Documentation/Historical/SwiftUI parity process/The semantic audit of August 2026.md` (item 8, and the verifiers' finding on labelled
  controls).

### Menu items and alert buttons

- **Asks:** what SwiftUI builds for the content of a menu — a `Picker` in each style, with a `Section` or a
  `Divider` among its options, disabled, unlabelled or matching nothing; a `Menu` nested two deep, empty,
  disabled, under `.menuStyle(.button)`, with a primary action, under `.help` or `.keyboardShortcut` — read back
  from the main menu's `NSMenu` items of a `CommandMenu` (`menus.swift` built with `-D CASE_pickers`,
  `pickers.out`); and which modifiers written on an alert's buttons the `NSAlert` it presents keeps — `.disabled`,
  a key equivalent, `.defaultAction`, `.cancelAction`, `.help`, `.tint`, `.foregroundStyle`, a role — read back
  from the alert panel's `NSButton`s (`-D CASE_alert`, `alert.out`; `-D CASE_dialog` for a
  `confirmationDialog`, `dialog.out`). The usage is at the top of `menus.swift`. And where an `.inline` picker's
  separators fall in a menu — first, last, beside a `Divider`, a `Section` or another inline picker — read back the
  same way (`inline.swift`, `inline.out`); and which separators AppKit DRAWS, from the height of the menu window of
  plain `NSMenu`s popped up with leading, trailing and doubled separators (`shown.swift`, `shown.out`).
- **Answers:** a `Picker` of the menu, segmented or palette style is a submenu titled by its label, its options
  items with the selected one checked; an `.inline` one is its label as a section header over its options,
  between separators; a nested `Menu` is a submenu whatever its style, and a disabled one is a submenu of
  disabled items. An alert keeps `.disabled` and the key equivalent (`.defaultAction` is Return, `.cancelAction`
  Escape) and shows none of `.help`, `.tint` and `.foregroundStyle`. SwiftUI builds an `.inline` picker as it
  builds a `Section` — a separator either side of a section-header item, wherever it stands, so a menu's items
  can begin, end or double up on separators — and AppKit draws none of those: no separator at the top or bottom
  and never two in a row (`- A B` and `A - - B` draw as tall as `A B` and `A - B`).
- **Ran:** macOS 15.8, 2026-10-19, with Xcode's `swiftc`; the window the alert is presented on is made by the
  probe, since a `WindowGroup` opened none in that session.
- **Was:** `MENUS/probe/`.
- **Cited by:** `Sources/TUIPresentation/Views/AlertActions.swift`,
  `Sources/TUIFoundation/Rendering/MenuSubmenus.swift`, `Sources/TUIMenus/Views/_MenuPopupCore.swift`,
  `Sources/TUIPickers/Views/Picker.swift`, `Sources/TUIPickers/Views/PickerMenuRows.swift`,
  `Sources/TUIFoundation/Rendering/MenuSections.swift`;
  `Tests/TUIPresentationTests/AlertButtonModifierTests.swift`, `Tests/TUIMenusTests/MenuSubmenuTests.swift`,
  `Tests/TUIIntegrationTests/PickerInMenuTests.swift`, `Tests/TUIIntegrationTests/MenuBarSubmenuTests.swift`;
  `Documentation/SwiftUI parity/SwiftUI compatibility guide.md` (§1, Controls; Presentation),
  `Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md` (W15, W16),
  `Documentation/Historical/Menus, toolbars and chrome/Pop-up menus: submenus, type select and an alert's buttons.md`.

### Blend modes

- **Asks:** what `View.blendMode(_:)` does to each pixel for every mode: over an opaque backdrop, beside the source
  where it does not reach, with the source at half opacity, and over nothing; which space the formulas work in
  (encoded sRGB or linear light); and what the Porter-Duff modes leave where the source is and where it is not
  (`blendmodes.swift`, `blendmodes.out`). Renders with `ImageRenderer` at scale 1 and reads the pixels back in
  sRGB.
- **Answers:** one line per mode in `blendmodes.out`; what TUI takes from them (the formulas work on the
  encoded sRGB values, macOS's soft light, where alpha comes in) is worked through in the EFFECTS decisions. Over
  nothing every mode but the Porter-Duff ones draws the source unchanged; source atop and destination out draw
  nothing there, and destination over leaves the backdrop wherever there is one.
- **Ran:** macOS 15.8, the macOS 26.2 SDK, 2026-10-19.
- **Cited by:** `Sources/TUICore/Rendering/BlendMode.swift`,
  `Sources/TUIFoundation/Styling/Color+BlendMode.swift`; `Tests/TUIFoundationTests/BlendModeTests.swift`;
  `Documentation/Colour and styling/Opacity as composition.md`,
  `Documentation/Historical/Shapes, effects and animation/Pixel effects: transforms, masks, drawingGroup, blend modes and meshes.md`.

### Search field clear button

- **Asks:** what a macOS search field shows at its trailing end while it is empty and while it holds text, and
  what its cancel button's action and Escape (`cancelOperation`) do to the text (`searchclear.swift`,
  `searchclear.out`). SwiftUI's `.searchable` on macOS is an `NSSearchField` in the toolbar, so the field is made
  directly, rendered with `cacheDisplay(in:to:)` to two PNGs, and the PNGs read by eye.
- **Answers:** empty, the field shows the magnifier and the prompt and nothing at its trailing end; with text, a
  filled grey ⓧ there. Its action and Escape both empty the field.
- **Ran:** macOS 15.8.1, Xcode's `swiftc`, 2026-10-19.
- **Cited by:** `Sources/TUISearch/Modifiers/SearchableModifier.swift`,
  `Tests/TUISearchTests/SearchableTests.swift`; `Documentation/SwiftUI parity/SwiftUI compatibility guide.md`
  (the clear button row), `Documentation/Terminals/Terminal compatibility survey.md` ("The search field's ✕").

### Vertical TextField keys, caret and size (wave 6b)

- **Asks:** what a `TextField(axis: .vertical)` does with each newline-ish key (`keys.swift`); how the caret moves:
  Up and Down across hard and soft lines and off either end, Ctrl-A, E, K, P and N, Home and End, in typed-in
  multi-line text (`nav.swift`); on which of two wrapped rows the insertion point is drawn at the wrap, and what
  the field editor's `selectionAffinity` says, after a click-like set, an arrow key, typing and End
  (`affinity.swift`); and how the field is sized: its growth with wrapped text, under each `lineLimit` form, and
  with a long prompt (`size.swift`). Each puts the field in an `NSWindow` and sends key events through its key path.
- **Also:** `affinity-motions.swift` (`affinity-motions.out`): the lean the field editor gives an insertion point
  at a wrap after the motions `affinity.swift` did not try — Backspace and Forward Delete (from either lean), Down
  and Up, ⌘← and ⌘→, Ctrl-A and Ctrl-E, an arrow, a word move (D4X-FULLER, 2026-10-27).
- **Files:** `keys.swift`, `nav.swift`, `affinity.swift`, `size.swift`, `affinity-motions.swift`. Only
  `affinity-motions.out` was kept: the other results are in the citing documents.
- **Ran:** macOS 15.8, the macOS 26.2 SDK, 2026-10-03; `affinity-motions.swift` 2026-10-27.
- **Was:** `w06b/probe/`.
- **Cited by:** wave 6b's entries in `Documentation/Historical/` (found by id through its `Index of decision ids.md`);
  `Documentation/SwiftUI parity/Design studies/Text selection and editing design study, A13, A42 and A43 (2026-10-04).md`.

### Table questions, compile and runtime (wave 8a)

- **Asks:** compile-only questions about SwiftUI's `Table` surface, checked with `swiftc -typecheck`: which
  initialiser a key-path column picks, whether a key path's root is inferred inside a `Group` of columns, and the
  corpus's row and customization shapes (`compile1.swift` to `compile4.swift`); and, run against the macOS SDK, what
  a `Table` does at run time (`run1.swift`), where a column's alignment puts a short cell (`run2.swift`) and what
  each `TableStyle` draws: the `NSTableView` style, grid lines, stripes, the scroll view's border (`run3.swift`).
  `common.swift` hosts a view offscreen for the three `run` programs.
- **Also:** `never_sort.swift` and `linuxcheck/` (whether `Never` is a `SortComparator`, and whether
  `Locale.NumberingSystem` and `SortDescriptor` are there on Linux), `dbgtype/` (a fix attempt for a column and a
  row protocol that both refine one base: each redeclares its associated type with a default, and a user type
  relies on the default), and `tk_group.swift`, the TUI side of `compile2.swift`. These ask the compiler, not
  SwiftUI.
- **Ran:** macOS 15.8, the macOS 26.2 SDK, 2026-10-03.
- **Was:** `w08a/probe/`.
- **Cited by:** wave 8a's entries in `Documentation/Historical/` (found by id through its `Index of decision ids.md`).

### Tab badges, sections and customization (wave 8b)

- **Asks:** what a SwiftUI `TabView` draws in each style, with a section, a badge and a search-role tab
  (`tabs.swift`); what a tab's content reads for `\.tabBarPlacement` and `\.isTabBarShowingSections` under each style
  (`tabenv.swift`); `defaultVisibility(_:for:)` for each placement under each style, and a `TabViewCustomization`
  that hides a tab from the sidebar (`custom.swift`); `Section(isExpanded:)` in a `List` per list style, expanded
  and collapsed (`sections.swift`); and how a `List` row's badge draws under each `BadgeProminence`, in a plain list
  and in the sidebar style (`badge.swift`, `badge_sidebar.swift`).
- **Files:** the six `.swift` files. They write PNGs of what they drew to `NSTemporaryDirectory()`; the PNGs are not
  kept here.
- **Ran:** macOS 15.8, the macOS 26.2 SDK, 2026-10-03 and 2026-10-04. macOS 26 API could not be probed.
- **Was:** `w08b/probe/`.
- **Cited by:** wave 8b's entries in `Documentation/Historical/` (found by id through its `Index of decision ids.md`).

### Scroll geometry, margins and the wheel (wave 10)

- **Asks:** with `contentMargins` of every kind: where a `ScrollView`'s content insets land and how nested margins
  compose (`marg.swift`), where the first row of a `List`, a `Form` and a `Table` sits (`list.swift`, `form.swift`),
  what `containerRelativeFrame` fills (`crf.swift`), and where a `TextEditor`'s first ink is, against
  `safeAreaPadding` (`te.swift`); what `onScrollGeometryChange`, `onScrollPhaseChange` and `ScrollPosition`
  report across a `scrollTo` and an animated one (`geo.swift`); which rows `onScrollVisibilityChange` and
  `onScrollTargetVisibilityChange` call visible (`vis.swift`); and what a wheel event does to the scroll phase
  (`wheel.swift`). `ah.swift` is compiler-only: whether a `Hashable & Sendable` metatype survives a cast through
  `AnyHashable`.
- **Files:** the ten `.swift` files; `common.swift` is the offscreen host.
- **Ran:** macOS 15, 2026-10-03.
- **Was:** `w10/probe/`.
- **Cited by:** wave 10's entries in `Documentation/Historical/` (found by id through its `Index of decision ids.md`).

### Live text formats read back (wave 11a)

- **Asks:** what SwiftUI shows for its live and formatted texts. `ax.swift` and `ax2.swift` read a hosted `Text`
  through the accessibility tree; `ocr.swift` and `ocr2.swift` render it and run OCR on the picture, because the
  tree is empty without an assistive client; `pause.swift` is `Text(timerInterval:pauseTime:countsDown:)` with the
  pause before, inside and after the interval; `variant.swift` and `variant2.swift` ask whether
  `.textVariant(.sizeDependent)` changes a text short of room, and the ladder of readings each live text passes
  through as the width falls. `fmt.swift` and `fmt2.swift` format fixed dates and durations in `en_US` through the
  `SystemFormatStyle` family; `foundation_cmp.swift` does the same with Foundation's own formatters, the
  candidates for reproducing them; `ranges.swift` asks which bound a discrete format moves for a `Range<Date>`
  input, what a `Duration.TimeFormatStyle`'s discrete boundaries are, and whether `FoundationEssentials` imports.
- **Files:** the `.swift` files and the results they printed, `*_results_macos15.txt` and
  `foundation_cmp_macos15.txt`, each named for its program; `anchored_vs_reference_macos15.txt`, a table of
  anchored relative-date readings, has no program of its own here.
- **Ran:** macOS 15, 2026-10-03. A pass on macOS 26 is owed.
- **Was:** `w11a/probe/`.
- **Cited by:** wave 11a's entries in `Documentation/Historical/` (found by id through its `Index of decision ids.md`).

### Foundation shims and a text snapshot (wave 17)

- **Asks:** `p.swift`, for the refusal review: whether a modifier changes a hosted view's size or its pixels,
  compared with the same view without it (`submitLabel`, `font.leading`, `symbolRenderingMode`, `controlSize`,
  `textScale`, `imageScale`, `scenePadding`, `fontDesign`, `contentShape`, `sensoryFeedback`, `allowsTightening`);
  and `lx.swift` to `lx5.swift`, small Foundation programs (`AttributedString` with Markdown and links, `CGAffineTransform`,
  `FileWrapper`, `NumberFormatter.getObjectValue`, `ReferenceConvertible`) built for the static Linux SDK to see
  which of them compile there.
- **Ran:** `p.swift` on macOS 15.8, 2026-10-03; `lx*.swift` with Swift 6.3.3's static Linux SDK.
- **Was:** `w17/probe/`.
- **Cited by:** `Documentation/Historical/SwiftUI parity process/The refusals re-examined (wave 17).md`.

### Spring loading (lane 17d)

- **Asks:** what SwiftUI does when a drag hovers over a spring-loading target: where spring loading is offered, with
  which options, and what activating does (`spring.swift`, `spring6.swift`, and the same question driven with a
  fake `NSDraggingInfo` in `spring2.swift`, `spring5.swift`); and the same for a `TabView`, with the window on
  screen (`spring3.swift`, `spring4.swift`). Each has its `.out`. And whether a `ColorPicker`'s colour well
  spring-loads under each behavior, the same fake drag scanned over it (`spring7.swift`, `spring7.out`): it does
  not, under any, and its `NSColorWell` is no `NSSpringLoadingDestination` (owner ruling B82).
- **Ran:** macOS 15.8, the macOS 26.2 SDK, 2026-10-04; `spring7.swift` macOS 15.8.1, 2026-10-24. The drag-session
  family is macOS 26's and is from its doc comments.
- **Was:** `w17d/probe/`.
- **Cited by:** lane 17d's entries,
  B82 in `Documentation/Historical/` (found by id through its `Index of decision ids.md`); `Sources/TUIColorPicker/Views/ColorPicker.swift`.

### Gestures (lane 17g)

- **Asks:** what SwiftUI's gestures do with synthesised `NSEvent`s sent into a window: the arbitration between a
  parent's gesture and a child's (`arb.swift`, `arb2.swift`), the thresholds of a tap, a double tap, a long press
  and a drag: the double-tap window, how long a tap may be held, how far it may travel, a release outside the view
  (`taps2.swift`), a tap with modifiers, a long press with and without a tap beside it, its pressing callback and
  maximum distance, and a gesture cancelled by a parent's high-priority drag (`taps3.swift`), and a drag's values
  and their timing (`timing.swift`). `common.swift` is the window harness. `combo.out`, `drag.out`, `lp.out` and
  `taps.out` are results whose programs are not kept.
- **Ran:** macOS 15.8, the macOS 26.2 SDK, 2026-10-04.
- **Was:** `w17g/probe/`.
- **Cited by:** lane 17g's entries in `Documentation/Historical/` (found by id through its `Index of decision ids.md`),
  `Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md`.

### Mesh gradient fits (lane 17m)

- **Asks:** what pixels SwiftUI's `MeshGradient` draws, and which model of its geometry and its smooth and
  perceptual colour rules fits them. `mesh.swift`, `mesh2.swift` and `mesh3.swift` render one mesh per case through
  `ImageRenderer` at scale 1 and write the RGBA bytes to a directory (`./mesh OUTDIR`); `anim.swift` asks whether a
  mesh animates inside `withAnimation`. The Python files read those dumps and fit models to them: `model.py` the
  geometry, `bezier_check.py` the explicit Bézier points, `fit.py` a bicubic patch fitted to the coordinates the
  colours encode, `tanfit.py` the vertex tangents, `colour.py`, `colour2.py`, `colour3.py`, `row1d.py`, `cs1d.py`,
  `hue1d.py`, `lms.py` and `lms_rows.py` the colour rule,
  `errmap.py` a model's error per block, `pins.py` the pixels the tests pin, `px.py` a reader for a dump.
- **Not kept:** the `.rgba` dumps (several MB). Run `mesh.swift`, `mesh2.swift` and `mesh3.swift` to make them
  again; the scripts name the cases.
- **Ran:** macOS 15.8, the macOS 26.2 SDK, 2026-10-04.
- **Was:** `w17m/probe/`.
- **Cited by:** lane 17m's entry in `Documentation/Historical/` (found by id through its `Index of decision ids.md`),
  `Tests/TUIFoundationTests/MeshGradientTests.swift`.

### Coordinate spaces and scroll visibility (D5G)

- **Asks:** where a view in a scroll view reports itself in each coordinate space, and what the scroll view's
  offset does to it (`m3.swift`, `m3b.swift`: a reader's frame and bounds in `.scrollView`, a named space and `.global`, with a
  `ScrollPosition(y: 40)` against the scroll view scrolled by AppKit);
  which scroll view `.scrollView` picks when a horizontal one sits in a vertical one (`m4.swift`); the phases each
  row's `scrollTransition` closure is called with (`st.swift`); and `onScrollVisibilityChange` at several thresholds, for views inside and
  outside the scroll view (`vis.swift` to `vis6.swift`, each later one refining the case of the one before).
  `st2.swift` tried to find the default threshold from a picture of the faded band, and did not agree with
  itself, so the default is taken as `.visible`.
- **Files:** the `.swift` files and their `.out` where one was kept (`m3`, `m3b`, `m4`, `st`, `st2`, `vis`, `vis2`,
  `vis3`).
- **Ran:** macOS 15, 2026-10-05.
- **Was:** `D5G/probe/`.
- **Cited by:** `Documentation/Historical/Layout and geometry/README.md`;
  `Documentation/Historical/Layout and geometry/Where a view is: coordinate spaces, geometry readers and scroll visibility.md`.

### Scroll position, margins and disabled scrolling (DECB)

- **Asks:** which anchor wins when a transaction's `scrollTargetAnchor` and a call's own disagree (`anchor/`);
  what SwiftUI does under `Transaction.scrollContentOffsetAdjustmentBehavior = .disabled` (`disabled/`); where an
  `NSScroller` goes under `contentMargins`, by placement, for overlay and legacy scrollers (`margins/`); and what
  velocity is in a `ScrollPhaseChangeContext` at each change that can be made to happen offscreen (`phase/`). Each
  folder holds its `.swift` and its `.out`.
- **Also:** the lane's reading of how AppKit mirrors a key equivalent under a right-to-left layout (decisions B8):
  `mirror.swift` (`mirror.out`) lists the characters AppKit's private mirroring candidates cover and what each
  becomes, and `findsel.swift`, `findsel2.swift`, `imgs.swift` and `ksc.swift` (`ksc.out`) search the Objective-C
  runtime for the selectors that do it. They call private AppKit and TextInput selectors, which is why they are
  here and not in TUI.
- **Ran:** macOS 15.8, 2026-10-12.
- **Was:** `DECB/probe/`.
- **Cited by:** `Documentation/Historical/` (found by id through its `Index of decision ids.md`),
  `Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md`.

### Shape paths (W1)

- **Asks:** SwiftUI's own descriptions of the paths its `Path` builders and shapes make (`paths.swift`: a
  triangle, arcs drawn both ways, relative and tangent, a rectangle, an ellipse, rounded rectangles circular,
  continuous, uneven and with too large a radius, the built-in shapes, trimmed paths, insets, offset, rotation and
  scale, each with its bounding box), and how its rounded rectangle clamps a corner size larger than the rectangle
  (`clamp.swift`). `iso/` (`iso.swift` to `iso4.swift`) and `onlytuikit/` are isolation experiments on a
  stand-in `Shape` and `View` protocol pair, and on TUI alone; they say nothing about SwiftUI's behaviour.
- **Also:** `review/` is the lane's review round: `desc.swift`, `addarc.swift` and `cap.swift` (SwiftUI's
  descriptions of the arcs the review's fixes pin, of `addArc` past a turn and of a relative arc's segmentation
  near the cap, where it stops adding quarter turns), `arcs.swift` (how CoreGraphics and SwiftUI build arcs of
  non-finite or huge angles, and how CoreGraphics dashes an odd-length or a very fine pattern) and
  `dashfine.swift` (where CoreGraphics stops drawing a pattern as dashes and draws the line whole, and what a very
  long dashed line costs).
- **Ran:** macOS 15.8, 2026-10-18.
- **Was:** `W1/probe/` and `W1/probe2/`.
- **Cited by:** `Documentation/Historical/Shapes, effects and animation/Shapes.md`;
  `Sources/TUIFoundation/Shapes/Path+Builders.swift`, `Sources/TUIFoundation/Rendering/ShapeStroker.swift`;
  `Tests/TUIFoundationTests/PathTests.swift`, `Tests/TUIFoundationTests/ShapeTests.swift`.

### Insertion and removal (FB16)

- **Asks:** whether SwiftUI moves a view's siblings when the view is inserted or removed with a transition that
  does not move it (opacity, scale, identity). `FB16Probe.swift` builds five columns (`opacity`, `scale`,
  `move top`, `identity`, `push`), each inserting its middle row with one transition under an 8 s linear
  animation, on a loop (shown 10 s, hidden 10 s); `samples.txt` is the Core
  Animation presentation frames every 0.5 s, per column and per phase (`insert` and `remove` lines).
- **Ran:** macOS 15.8, 2026-10-17.
- **Was:** `plan/fb16/`.
- **Cited by:** `Documentation/Historical/Shapes, effects and animation/Inserting and removing views: transitions and the default fade.md`,
  `Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md`; `Sources/TUIEffects/Animation/TransitionModifier.swift`,
  `Sources/TUIFoundation/Views/StackGlide.swift`, `Sources/TUIView/Animation/ChildGlide.swift`,
  `Sources/TUIView/Animation/PlacementStore.swift`; `Tests/ExampleTests/AnimationPageShowHideTests.swift`,
  `Tests/TUIEffectsTests/DefaultTransitionTests.swift`, `Tests/TUIEffectsTests/StackGlideTests.swift`,
  `Tests/TUIEffectsTests/TransitionTests.swift`.

### Small parity items (PARITYMISC)

- **Asks:** whether SwiftUI parses Markdown in a `Tab` title, a `TableColumn` header and a `TextField` title
  (`b87/`: `probe.swift` reads the AppKit views a hosted view makes; `tabs.swift` to `tabs4.swift` dump the view
  tree of a `TabView` with a Markdown tab title; the renders they also made are not kept); how a `Text` key is looked up under `\.locale`, with `en`, `de`
  and `fr` tables and without a table for `pt` or `ja` (`locale/probe.swift`; it needs a bundle, so build it as
  `Probe.app/Contents/MacOS/probe` with `Info.plist` and `Resources/` beside it); what a `Binding<AnyHashable>`
  made from a `Binding<Int>` does on a read, and on a write of an `Int`, an `Int8` and a `String`
  (`binding_anyhashable.swift`);
  whether `.scrollIndicators(_:axes:)` shows the AppKit scrollers (`shows_indicators.swift`); and the number of
  `NSTextContentType` cases (`tct.swift`). `entry_probe.swift` (SwiftUI's `@Entry`) and `entry_diag.swift` (TUI's
  macro's diagnostics) check the `@Entry` macro on both sides.
- **Ran:** macOS 15, 2026-10-18.
- **Was:** `PARITYMISC/probes/`.
- **Cited by:** `Documentation/Historical/Text, editing and the clipboard/Text fields and the wrapping editor.md`,
  `Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md`.

### Undo and the pointer leaving (INPUT)

- **Asks:** whether `NSTextView` coalesces a run of typing into one undo step, and what ends the run: a pause, a
  caret move, a deletion (`undo.swift`); what ends it beyond those: the first responder moving to another text view
  that shares the window's undo manager and back, an unrelated undo registered on that manager mid-run,
  Option-Return and Ctrl-O (`undo2.swift`); and whether an undo group's user info names the newest step, so that a
  text control can ask whether its run's step is still the newest (`undo3.swift`).
- **Also:** `pointer_leave_probe.py` is not a SwiftUI probe: a PTY check of the Example app for the pointer
  leaving a help view, written for BUGS13-POINTER-LEAVE.
- **Ran:** macOS 15.8, 2026-10-18.
- **Was:** `INPUT/probes/` (the three programs were `undo/main.swift`, `undo2/main.swift` and `undo3/main.swift`).
- **Cited by:** `Documentation/Historical/Input, keys and gestures/The kitty keyboard protocol and modified keys.md`;
  `Sources/TUIFoundation/Focus/TextUndoBridge.swift`, `Sources/TUITextInput/Focus/TextUndoHistory.swift`;
  `Tests/TUITextInputTests/TextUndoCoalescingTests.swift`.

### Markdown attribute syntax

- **Asks:** what Foundation's Markdown parser does with Apple's `^[text](attributes)` when the attributes do not
  parse, and how it finds the `)` that ends them: forty-odd cases parsed with `.inlineOnlyPreservingWhitespace`,
  each one's characters printed (B86's open item).
- **Files:** `attrs.swift`, `attrs.out`.
- **Ran:** macOS 15.8, Xcode's Swift 6.2.4, 2026-10-27.
- **Cited by:** `Sources/TUIStrings/Rendering/InlineMarkdownParser.swift`;
  `Documentation/Historical/Text, editing and the clipboard/Links, Markdown and attributed text.md`.

### Picker pop-up highlight

- **Asks:** which item a `.menu`-style `Picker`'s pop-up highlights when the pointer opens it: the current value, or
  none, as a pointer-opened `Menu` does in TUI (PICKER-POINTER-OPEN). It clicks the `NSPopUpButton` SwiftUI made
  (`performClick`) and reads the menu's highlighted item from inside its tracking loop.
- **Files:** `popup.swift`, `popup.out`: the current value ("Banana") is highlighted.
- **Ran:** macOS 15.8, Xcode's Swift 6.2.4, 2026-10-27.
- **Cited by:** `Documentation/Historical/Menus, toolbars and chrome/Pop-up menus: submenus, type select and an alert's buttons.md`.

### The menu bar (O13)

- **Asks:** what SwiftUI puts in the main menu for a few `.commands` shapes: the order of the menus, how a
  `CommandGroup`'s three positions compose, what `commandsRemoved()` and `commandsReplaced` take away, what the
  standard command sets add. It builds a SwiftUI app per case and reads the main menu back: `menus.swift`, with
  `run.sh <case>` (cases `base`, `two`, `removed`, `removedInner`, `replaced`, `order`, `keys`). The probe could not
  make its window key on the development Mac, and with no key window the main menu took the key, so how a command's
  key equivalent is routed is unmeasured. Cases `toolbarId` and `toolbarIdStd` host a page with a customizable
  toolbar (`toolbar(id:)`) in a window of the probe's own and read the View menu without and with `ToolbarCommands`
  (`toolbarId.out`, `toolbarIdStd.out`): without, it holds no Customize Toolbar…; with, Show Toolbar and Customize Toolbar… (disabled, the
  window not being key).
- **Ran:** macOS 15.8, 2026-10-18; the toolbar cases on macOS 15.8.1, 2026-10-29.
- **Was:** `O13/probe/`.
- **Cited by:** `Documentation/Historical/Menus, toolbars and chrome/The menu bar.md`,
  `Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md`,
  `Documentation/SwiftUI parity/SwiftUI compatibility guide.md`; `Sources/TUIApp/App/SceneCommandsDeclaration.swift`,
  `Sources/TUICommands/Commands/CommandGroup.swift`, `Sources/TUICommands/Commands/CommandGroupPlacement.swift`,
  `Sources/TUICommands/Commands/CommandMenu.swift`, `Sources/TUICommands/Commands/CommandsCollector.swift`,
  `Sources/TUICommands/MenuBar/SceneOwnCommands.swift`, `Sources/TUICommands/Scene+Commands.swift`,
  `Sources/TUIFoundation/Views/KeyboardShortcutRegistry.swift`;
  `Tests/TUICommandsTests/CommandsCollectionTests.swift`.

### Dropped members (RC5)

- **Asks:** what SwiftUI shows of content that is not what its container sorts its members by: a `Picker`'s
  members with no tag, a tag of another type than the selection, a `nil` tag under an optional selection, a
  `Toggle` and a `Button`, read back from a `CommandMenu`'s `NSMenu` items (`dropped.swift` built with
  `-D CASE_pickers`, `pickers.out`); and an alert's actions that are not buttons — a `TextField`, a
  `SecureField`, a `Text`, a `Toggle`, an `Image`, and a button and a text field each inside a view of the app's
  own — read back from the alert panel's AppKit views (`-D CASE_alert`, `alert.out`).
- **Answers:** every picker member is an item of the menu, enabled, tagged or not and whatever its tag's type.
  An alert shows its text fields and secure fields (the one inside a view of the app's own too), and a toggle as
  a button titled by its label; it leaves out a `Text` and an `Image`.
- **Ran:** macOS 15.8.1, Xcode's `swiftc`, the macOS 26.2 SDK, 2026-10-24.
- **Cited by:** `Sources/TUIFoundation/Views/DroppedMembers.swift`,
  `Sources/TUIPickers/Views/_PickerOptionsReader.swift`, `Sources/TUIPresentation/Views/AlertActions.swift`;
  `Documentation/Historical/SwiftUI parity process/The semantic audit of August 2026.md` (root cause 5).

### Named colours by scheme

- **Asks:** what SwiftUI's fifteen named colours resolve to under a light and a dark colour scheme, and in a bare
  `EnvironmentValues` (what a view body sees), with `Color.resolve(in:)`; and what AppKit's `NSColor.systemRed`
  and friends are under the aqua and darkAqua appearances, converted to sRGB, as a cross-check
  (`namedcolours.swift`, `namedcolours.out`). No view: top-level code, built alone.
- **Answers:** a bare environment answers the light values. Thirteen names have a dark value of their own, which
  is AppKit's darkAqua value; `.white` and `.black` are the same in both.
- **Ran:** macOS 15.8.1, Xcode's `swiftc`, the macOS 26.2 SDK, 2026-10-24.
- **Cited by:** `Sources/TUIStyling/Color/SystemColor.swift`, `Sources/TUIStyling/Color/Color.swift`,
  `Tests/TUIStylingTests/NamedColorTests.swift`;
  `Documentation/Historical/Colour and styling/Named colours, asset catalogues and dark values.md`
  (B-D6M-3).

### Interpolated values drawn (TEXTFMT)

- **Asks:** what SwiftUI draws for a value interpolated into a `Text`'s key with no specifier — an `Int`, an
  `Int8`, a `UInt`, a `Double`, a `Float`, in `en_US` and `de_DE` — and for a `Substring`, an `AttributedString`,
  and a `ClosedRange<Date>` and a `DateInterval`, interpolated and as `Text(_:)`; with Foundation's own interval
  formats beside the range's (`drawn.swift`, `drawn.out`). Each `Text` is rendered through `ImageRenderer` and read
  back by Vision, as "Live text formats read back (wave 11a)" does.
- **Answers:** a number is formatted through its printf conversion in the locale (`1,234,567`, `3.500000`;
  `1.234.567`, `3,500000`); a range of an hour reads `11:13 PM-12:13 AM` and one of days `May 8 - May 11`, with no
  year even 400 days apart, which is none of Foundation's interval formats.
- **Ran:** macOS 15.8.1, Xcode's `swiftc`, the macOS 26.2 SDK, 2026-10-24, in the `America/Los_Angeles` zone.
- **Cited by:** `Sources/TUIFoundation/Localization/LocalizedStringKey+Interpolation.swift`;
  `Documentation/Historical/Text, editing and the clipboard/Formatting and live text.md`
  (B-TEXTFMT-1, C-TEXTFMT-1).

### Live titles (TEXTFMT)

- **Asks:** which consumers of a title keep a live value live: a timer interpolated into a button's title, a text
  field's and a secure field's title (drawn as the placeholder), a table column's header and a window's navigation
  title (`titles.swift`, `titles.out`), and into an alert's title and message (`alert.swift`, `alert.out`). Each is
  a `WindowGroup` app that reads the window's title, the fields' `placeholderString`, the table's column titles,
  the alert panel's fields, and what is drawn (by Vision), at three times.
- **Answers:** live in the button, both placeholders and the header; read once (`0:00` throughout) in the window's
  title and the alert's title and message.
- **Ran:** macOS 15.8.1, Xcode's `swiftc`, the macOS 26.2 SDK, 2026-10-24.
- **Cited by:** `Documentation/Historical/Text, editing and the clipboard/Formatting and live text.md`
  (B51-LIVE), `Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md` (T5),
  `Sources/TUIFoundation/Views/Text+Markdown.swift`, `Sources/TUITextInput/Views/TextField.swift`,
  `Sources/TUITables/Views/TableColumn.swift`; `Tests/TUIIntegrationTests/LiveTitleTests.swift`.

### Effect and update ordering

- **Asks:** when SwiftUI runs a view's effects — `onAppear`, `onChange(of:)`, `onPreferenceChange`,
  `onGeometryChange(for:of:action:)`, `onScrollGeometryChange`, `.task` — against its body evaluations, a custom
  `Layout`'s calls, `GeometryReader` content, drawing (a `Canvas` renderer) and the Core Animation commit that
  carries a frame to the screen; whether the first frame drawn after a state write made in an effect shows the old
  state or the new; how many update passes a chain of effects gets per frame, and where the "tried to update
  multiple times per frame" warnings start; whether a `GeometryReader` is ever run with a provisional size; on which
  executor `.task` starts; and what a `@State` write inside `body` does. One program, `ordering.swift`, one case a
  process (`appear`, `change`, `chain`, `selfloop`, `prefloop`, `geofeedback`, `geocount`, `geoscroll`, `geolist`,
  `bodywrite`), each in an on-screen borderless window, logging one numbered line per event from an
  `NSHostingView` subclass's `updateConstraints()`/`layout()`, main run-loop observers at the lowest and highest
  order of every activity, a Core Animation post-commit handler (SPI `addCommitHandler:forPhase:`) that renders the
  committed layer tree, and the view's `CADisplayLink`. With `PROBE_STACKS` it prints the stack behind a few events.
- **Files:** `ordering.swift`; `run.sh`, which builds it with Xcode's `swiftc`, runs every case with
  `OS_ACTIVITY_DT_MODE=YES` (SwiftUI's runtime warnings appear in the log as `[runtime] …`) and writes
  `<case>.out`, its stacks demangled. The times and frame numbers in the `.out` files differ from run to run; the
  order of events did not, over four runs of each case, except in the two ways that
  `Documentation/Historical/State and dynamic properties/The update model: when effects run.md` names.
- **Answers:** no effect ran inside a body or inside a `Layout` call: SwiftUI runs them in `Update.dispatchActions()`,
  either from `ViewRendererHost.render(…)` inside `NSHostingView.layout()` or from `Update.end()` at the end of a
  graph update in SwiftUI's own run-loop observer. A state write in `onAppear`, `onChange` or `onPreferenceChange` is
  drawn before the first commit after it: no frame after the write shows the state before it. A layout pass re-renders
  after two rounds of effects at most, and that state is committed; the rest of a chain runs in SwiftUI's
  `beforeWaiting` observer (98 more `onChange` steps, 298 more `onGeometryChange` calls, no limit met) and is drawn in
  a second commit. The same `onChange` or preference action runs at most twice after a draw ("… tried to update
  multiple times per frame"); the change after that gets no call, then or later. `onGeometryChange` has no count
  limit, but stops when a value repeats one it delivered ("Geometry action is cycling between duplicate values."). A
  reader's content runs once per update, with that update's final size, never for a measuring proposal. `.task` starts
  after the first commit, on the main actor, whatever its priority. A write in `body` warns "Modifying state during
  view update, this will cause undefined behavior." and is lost.
- **Ran:** macOS 15.8.1 (SwiftUI of macOS 15.8.1), Xcode 26.3's `swiftc` (Swift 6.2.4), the macOS 26.2 SDK,
  2026-10-24.
- **Cited by:** `Documentation/Historical/State and dynamic properties/The update model: when effects run.md`.

### Modal sheet keys

- **Asks:** behind a window-modal sheet and an app-modal alert on macOS, which key equivalents still work: an app
  command (a main-menu item whose target is the app delegate, ⌘K), a window command (a main-menu item with no
  target, implemented by the document window's view, ⌘J) and a button's key equivalent in the window (⌘B). Each
  invocation and each menu validation is logged with what was modal at the time. AppKit, not SwiftUI: the question
  is the platform's rule, which a SwiftUI app's menus and buttons follow.
- **Files:** `modalkeys.swift` (build with `swiftc`, wrap it in an app bundle so the keys can be sent to it, run it,
  press the keys); `modalkeys.out`, the log of the run.
- **Answers:** with nothing modal all three run. Behind the sheet ⌘K runs; ⌘J and ⌘B do nothing, and the window
  command is disabled in the menu. Behind the app-modal alert nothing runs, and both menu items are disabled.
- **Ran:** macOS 15.8.1, Xcode's Swift 6.2.4, 2026-10-27, the keys sent by computer use.
- **Cited by:** `Sources/TUIFoundation/Views/KeyboardShortcutRegistry.swift` (`Scope`);
  `Documentation/Historical/Presentation and windows/Sheets: sizes, detents, live sheets and the page behind.md`
  (A-MODALS-1).
