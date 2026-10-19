# SwiftUI probes

Small programs that record what SwiftUI does, so that TUIkit can do the same. These are the ones that TUIkit's
doc comments, tests and decisions files cite, by path, as the measurement behind a claim about SwiftUI's
behaviour; each is kept with what it printed. Probes that nothing here cites stay in the maintainers' working
notes, and a document that cites one of those names its folder there.

Each probe is a short Swift program compiled with `swiftc` against the macOS SDK and run on a Mac. Most host SwiftUI
views in an `NSHostingView`, in a borderless window placed off-screen, and print what they read back: the frames
views were given (through a `GeometryReader` or a `Layout`), how many subviews a container counted, which
`@State` values a body saw, which `update()` calls ran, the colour of the pixels SwiftUI drew down a column. Some
read the AppKit views SwiftUI made instead (an `NSTableView`'s rows, an `NSMenu`'s items), and a few print a value
with no view at all. What a probe printed is in a `.out` file of the same name; a probe with no `.out` file
reported its result in the document that cites it.

One folder, Swift runtime layouts, records the Swift runtime's own layouts that TUIkit's property walk reads,
with no SwiftUI involved.

They are evidence, not part of the package: SwiftPM, CI and SwiftLint do not see them, and no binary or other
build product is kept here. `Tools/TerminalProbes/` is the same idea for terminals.

## Where they ran

On the development Mac, an Apple-silicon VM running macOS 15.8 (15.8.1 where a note gives the point release;
SwiftUI 6.5.4), against the macOS 26.2 SDK of Xcode 26.3, between 2026-10-03 and 2026-10-11; where the notes name
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
- **Cited by:** `Documentation/SwiftUI parity/Decisions/DynamicProperty update write-back (DYNP).md`;
  `Tests/TUIkitFoundationTests/DynamicPropertyTests.swift`, `Tests/TUIkitFoundationTests/ObservableInvalidationScopeTests.swift`. The
  probes of the next three folders reuse its harness.

### Dynamic property discovery

- **Asks:** which stored fields of a view SwiftUI visits for a `DynamicProperty`: a plain field, an optional, an
  existential (`any DynamicProperty`, `Any`), a generic, a modifier held or applied, a class, a `weak` field; and
  whether it runs a `ViewModifier`'s body when the body returns `content` unchanged. `notes.md` is the write-up:
  the answer, how discovery works, the measured matrix against TUIkit, and the divergences it found.
- **Files:** `op.swift` (built plain and with `-D OPTCONF`; `op.out`, `op-optconf.out`), `weak.swift`
  (`weak.out`), `passmod.swift` (`passmod.out`), `notes.md`. A second round, for the suspects of lane DYNV's bug
  hunt that `op.swift` did not measure (a property in a `let` field, one view value at two places, a class
  property's subclass, a modifier wrapped by `.transaction(_:)` or joined by `.concat(_:)`, a dead `unowned`
  field read first): `dv.swift` (`dv.out`) and `dv2.swift` (run as `./dv2 main` and `./dv2 deadfirst`, which may
  trap; `dv2-main.out`, `dv2-deadfirst.out`).
- **Ran:** macOS 15.8.1, SwiftUI 6.5.4, 2026-10-10; the second round 2026-10-11.
- **Was:** `DYNP/optional/`; the second round `DYNV/probe/`.
- **Cited by:** `Sources/TUIkitView/State/DynamicProperty.swift`,
  `Sources/TUIkitView/State/NestedPropertyBinding.swift`, `Sources/TUIkitView/State/PropertyPlans.swift`,
  `Sources/TUIkitView/State/State.swift`; `Tests/TUIkitFoundationTests/DynamicPropertyStateKeyTests.swift` and the other
  `DynamicProperty*Tests.swift` files, `Tests/TUIkitFoundationTests/StateSharedValueTests.swift`;
  `Documentation/SwiftUI parity/Decisions/State keys inside a DynamicProperty (SKEY).md`,
  `Documentation/SwiftUI parity/Decisions/Finding dynamic properties from declared types (DYNVFIX).md`,
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
- **Cited by:** `Sources/TUIkitView/State/PropertyWalk.swift`, `Sources/TUIkitView/State/PropertyWalk+Objects.swift`;
  `Documentation/SwiftUI parity/Decisions/Finding dynamic properties from declared types (DYNVFIX).md`.

### State keys in dynamic properties

- **Asks:** what SwiftUI does with the `@State` inside an enum view's cases, an enum property's cases and a
  multi-value payload, and (under `-D OPTCONF`) an optional property going `nil` and back. Each case prints what
  the body reads, after pokes through the `$state` bindings the bodies hand out.
- **Files:** `skey.swift`, `skey.out`, `skey-optconf.out`.
- **Ran:** macOS 15, SwiftUI 6.5.4, 2026-10-11.
- **Was:** `SKEY/probe/`.
- **Cited by:** `Sources/TUIkitView/State/NestedPropertyBinding.swift`, `Sources/TUIkitView/State/StateStorage.swift`;
  `Tests/TUIkitFoundationTests/DynamicPropertyStateKeyTests.swift`;
  `Documentation/SwiftUI parity/Decisions/State keys inside a DynamicProperty (SKEY).md`.

### Alignment guides

- **Asks:** whether an explicit alignment guide's value is used as given or clamped to the view's own size, in
  `VStack` and `HStack` for every alignment (`guide.swift`, `guide.out`); then the same question for `ZStack`,
  `LazyVStack`, a single child's `.frame` and `.overlay` placement, a stack inside a frame, and a stack whose
  region a flexible child sets (`guide2.swift` to `guide6.swift`, each with its `.out`; all share
  `guide.swift`'s harness).
- **Also:** `GuideProbeTests.swift`, a Swift Testing suite that records TUIkit's placements for the same matrix
  into `tuikit.out` (copy it into `Tests/TUIkitIntegrationTests` to run it; it was written against TUIkit at 45e9a1f7a and
  has not been re-checked against today's); `check.py`, which fits SwiftUI's rule and TUIkit's then rule to the
  two outputs (`python3 check.py`: 135 rows each, no mismatch) and says which of TUIkit's two rules made each of
  the 72 differing rows differ. `tuikit.out` records TUIkit before the fix this probe led to.
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
- **Cited by:** `Tests/TUIkitChromeTests/AlignmentGuideParityTests.swift`,
  `Tests/TUIkitChromeTests/AlignmentGuideContainerParityTests.swift`,
  `Tests/TUIkitFoundationTests/AlignmentGuideKindTests.swift`,
  `Tests/TUIkitFoundationTests/AlignmentGuideWrapperTests.swift`,
  `Tests/TUIkitFoundationTests/EmptyContentLayoutTests.swift`;
  `Sources/TUIkitView/Core/PrimitiveViews.swift`, `Sources/TUIkitFoundation/Modifiers/OverlayModifier.swift`,
  `Sources/TUIkitView/Rendering/StaticViewListCount.swift`;
  `Documentation/SwiftUI parity/Decisions/Alignment guides outside their view (GUIDE).md`.

### List pinned headers and row stripes

- **Asks:** which macOS `List` styles float (pin) their section headers, and what separator style their table view
  uses (`pin.swift`); which rows a `Table` of each style and a `List`, sectioned or not, tint with alternating
  backgrounds, sampling each row's background pixel (`phase.swift`, built with `common.swift`).
- **Ran:** macOS 15.8, 2026-10-06 and 2026-10-07. Neither output was kept; the results are in the D6L decisions.
- **Was:** `D6L/probe/` (`phase.swift` and `common.swift` in `D6L/probe/phase/`).
- **Cited by:** `Sources/TUIkitLists/Views/_ListCore.swift`, `Sources/TUIkitTables/Views/Table.swift`;
  `Documentation/SwiftUI parity/Decisions/List and table stripes, surfaces, pinned headers and separators (D6L).md`.

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
- **Cited by:** `Sources/TUIkitView/Core/AnyViewMembers.swift`, `Sources/TUIkitView/Rendering/CompositeMembers.swift`,
  `Sources/TUIkitForms/Views/FormContentExtraction.swift`, `Sources/TUIkitFoundation/Rendering/MenuSections.swift`,
  `Sources/TUIkitLists/Views/ListRowEditOwner.swift`; `Tests/TUIkitListsTests/AnyViewMembersTests.swift`,
  `Tests/TUIkitFoundationTests/SubviewLayoutTraitsTests.swift`, `Tests/TUIkitListsTests/ForEachRowMembersTests.swift`,
  `Tests/TUIkitListsTests/ForEachRowVaryingMembersTests.swift`,
  `Tests/TUIkitIntegrationTests/SectionPartsTests.swift`, `Tests/TUIkitListsTests/CompositeMembersTests.swift`,
  `Tests/TUIkitListsTests/ListMultiViewRowEditingTests.swift`,
  `Tests/TUIkitFormsTests/FormWrappedSectionTests.swift`, `Tests/TUIkitMenusTests/MenuSectionTests.swift`;
  `Documentation/SwiftUI parity/Decisions/Sections and subview counting in stacks and loops (D1S).md`.

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
- **Cited by:** `Tests/TUIkitIntegrationTests/PinnedRowSectionTests.swift`,
  `Tests/TUIkitGridTests/LazyGridSectionTests.swift`; wave 10b's entries in
  `Documentation/SwiftUI parity/Decisions/SwiftUI API completion decisions.md`.
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
- **Cited by:** `Sources/TUIkitView/Rendering/FieldDescriptors.swift`, `Sources/TUIkitView/State/EnumPayloads.swift`,
  `Sources/TUIkitView/State/DynamicTypes.swift`, `Sources/TUIkitView/State/State.swift` (`stamp.out`);
  `Documentation/SwiftUI parity/Decisions/Finding dynamic properties from declared types (DYNVFIX).md`.

### Localization keys

- **Asks:** what key SwiftUI's `LocalizedStringKey` records for each kind of interpolated value — every integer
  and floating-point width, `CGFloat`, `String`, `Text`, `Image`, `AttributedString`, a date style, format styles,
  `specifier:`, `NSNumber` with and without a formatter, a `ReferenceConvertible`, a date range, and a literal `%`
  beside a number — read from the key's stored `key` field (`keys.swift`, `keys.out`). No view is drawn.
- **Ran:** macOS 15.8, SwiftUI 6.5.4, Xcode's Swift 6.2.4, 2026-10-13.
- **Was:** `T10/probe/`.
- **Cited by:** `Sources/TUIkitFoundation/Localization/LocalizedStringKey.swift`;
  `Tests/TUIkitPresentationTests/SwiftUIKeySpellingTests.swift`; `Sources/TUIkit/TUIkit.docc/Articles/Localization.md`;
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
- **Cited by:** `Sources/TUIkitFoundation/Views/LayoutValueKey.swift`, `Sources/TUIkitView/Core/BufferModifier.swift`,
  `Sources/TUIkitFoundation/Views/StackGuidePropagation.swift`,
  `Sources/TUIkitFoundation/Rendering/LinearSpaceDistribution.swift`; `Tests/TUIkitFoundationTests/LayoutPriorityTests.swift`;
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
- **Cited by:** `Sources/TUIkitView/Animation/KeyframeCurve.swift`, `Sources/TUIkitCore/Animation/Animation.swift`;
  `Tests/TUIkitCoreTests/AnimationTimingTests.swift`, `Tests/TUIkitFoundationTests/KeyframeTimelineTests.swift`,
  `Tests/TUIkitFoundationTests/SpringTests.swift`, `Tests/TUIkitFoundationTests/UnitCurveTests.swift`; wave 12's entries in
  `Documentation/SwiftUI parity/Decisions/SwiftUI API completion decisions.md`.

### Transactions of observed changes

- **Asks:** which transaction SwiftUI updates a body under when one turn of the run loop writes two `@Observable`
  properties the body reads, one plainly and one inside `withAnimation`, in either order; and what an unanimated
  write followed by a `withAnimation` that writes nothing the body read (or nothing at all) is drawn under
  (`txn.swift`, a program of top-level code; `txn.out`). The body records, through `.transaction(_:)`, whether
  each update it was given carried an animation: SwiftUI updates it once per write, the animated write's update
  animated in both orders, and an empty `withAnimation` animates nothing.
- **Ran:** macOS 15.8.1, Xcode's Swift 6.2.4, 2026-10-18, in an `NSHostingView` with no window.
- **Was:** `APPSTATE/probe/`.
- **Cited by:** `Sources/TUIkitView/State/State.swift` (`AppState.transactionScopeEnded(_:)`);
  `Tests/TUIkitIntegrationTests/ObservedChangeTransactionTests.swift`;
  `Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md` (A7);
  `Documentation/SwiftUI parity/Decisions/Per-app render state (APPSTATE).md` (B-APPSTATE-2).

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
- **Cited by:** `Sources/TUIkitFoundation/Views/ScrollWindowHold.swift`,
  `Sources/TUIkitFoundation/Views/StackTopRowHold.swift`, `Sources/TUIkitLists/Focus/ItemListHandler+Anchor.swift`,
  `Tests/TUIkitTablesTests/ScrollWindowHoldTests.swift`; `Documentation/Layout and scrolling/Scroll
  anchoring.md` §5; `Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md` (R13, R14);
  `Documentation/SwiftUI parity/Decisions/Scroll anchoring default (SCROLLANCHOR).md`.

### Ragged text in a larger frame

- **Asks:** where SwiftUI draws the lines of a multi-line `Text` whose lines differ in width ("aaaa" over "bb")
  in a frame larger than the `Text`, wider or taller, under each frame alignment and each `multilineTextAlignment`:
  each line placed by the frame on its own width, or the `Text` placed as one block, its lines aligned inside it
  (`ragged.swift`, `ragged.out`). A program of top-level code; monospaced, so one character's advance stands in
  for a cell, and each line's ink is found in the pixels drawn. The block, in every case: in a 10-wide centred
  frame both lines start 3 characters in.
- **Ran:** macOS 15.8.1, SwiftUI 6.5.4, Xcode's Swift 6.2.4, 2026-10-13.
- **Was:** written for lane BUGS13 (`BUGS13/probe/`).
- **Cited by:** `Sources/TUIkitFoundation/Modifiers/FrameModifier.swift`; `Tests/TUIkitIntegrationTests/PlacementOverflowTests.swift`;
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
- **Cited by:** `Sources/TUIkitForms/Styles/LabeledContentStyle.swift`; `Tests/TUIkitIntegrationTests/LabeledContentTests.swift`,
  `Tests/TUIkitIntegrationTests/FormTests.swift`; `Documentation/SwiftUI parity/SwiftUI compatibility guide.md`.

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
- **Cited by:** `Sources/TUIkitFoundation/Views/ViewSpacing.swift`, `Sources/TUIkitFoundation/Views/Layout.swift`,
  `Sources/TUIkitFoundation/Views/StackSpacingPreference.swift`, `Sources/TUIkitView/Rendering/ChildInfo.swift`;
  `Tests/TUIkitGridTests/ViewSpacingTests.swift`, `Tests/TUIkitGridTests/StackSpacingPerPairTests.swift`;
  `Documentation/SwiftUI parity/SwiftUI compatibility guide.md` (the Layout row); B20 in
  `Documentation/SwiftUI parity/Decisions/SwiftUI API completion decisions.md`;
  `Documentation/SwiftUI parity/Decisions/Default focus, drop badges and stack spacing (BITEMS1).md`.

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
- **Cited by:** `Sources/TUIkitFoundation/Modifiers/FlexibleFrameAxis.swift`;
  `Tests/TUIkitFoundationTests/FlexibleFrameSwiftUIRuleTests.swift`;
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
- **Cited by:** `Sources/TUIkitEffects/Geometry/MatchedGeometryEffect.swift`;
  `Tests/TUIkitEffectsTests/MatchedGeometryEffectTests.swift`; `Documentation/SwiftUI parity/Deliberate
  deviations from SwiftUI.md` (A8), `Documentation/SwiftUI parity/SwiftUI compatibility guide.md` (the
  Animation row); `Documentation/SwiftUI parity/Decisions/Matched geometry and the zoom transition (O4).md`.

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
- **Cited by:** `Sources/TUIkitFoundation/Styling/ShapeStyle+Shadow.swift`,
  `Tests/TUIkitIntegrationTests/ShapeStyleShadowTests.swift`; `Documentation/SwiftUI parity/Decisions/What the
  shapes unblocked (W1B).md` (B-W1B-1).

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
- **Cited by:** `Sources/TUIkitFoundation/Styling/ImagePaint.swift`, `Sources/TUIkitFoundation/Styling/ShapeStyle.swift`
  (`in(_:)`), `Tests/TUIkitBitmapsTests/ImagePaintTests.swift`;
  `Documentation/SwiftUI parity/Decisions/What the shapes unblocked (W1B).md` (B-W1B-4).

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
  what a view draws displaced by `.offset`, with no transition and with `.opacity`. Each is a program alone
  (`@main`, built with `-parse-as-library`); `tr2` and `tr3` copy `tr1`'s harness.
  Found: with no transition the leaving view fades out where it was, drawn beneath its siblings, while the new
  one fades in and the views below glide — a branch flip, a `switch` case and a `ForEach` row alike, and a
  whole body's two branches overlap at its origin; each half of an `asymmetric` transition keeps its own
  animation, and a half with none takes the change's; the animation nearest the view wins, `nil` included,
  which plays the transition at once under any `withAnimation`; a transition's own animation plays with no
  `withAnimation`; each part of a `combined` transition runs under its own; a collapsing transition's
  neighbours move continuously as its frame shrinks; a view drawn displaced fades with the view it belongs to.
- **Ran:** macOS 15.8, Xcode 26's SDK and Swift 6.2.4, 2026-10-19. Samples move by a point or two, and an
  opacity by a hundredth, with the frame's timing.
- **Was:** `TRANSITIONS2/probe/`.
- **Cited by:** `Sources/TUIkitEffects/Animation/AnyTransition.swift`,
  `Sources/TUIkitEffects/Animation/TransitionModifier.swift`, `Sources/TUIkitEffects/Animation/TransitionEffects.swift`,
  `Sources/TUIkitView/Animation/DefaultTransition.swift`, `Sources/TUIkitView/Animation/ChildFade.swift`,
  `Sources/TUIkitView/Animation/BranchTransition.swift`; `Tests/TUIkitEffectsTests/TransitionTests.swift`,
  `Tests/TUIkitEffectsTests/TransitionAnimationTests.swift`, `Tests/TUIkitEffectsTests/BranchAndRowFadeTests.swift`,
  `Tests/TUIkitEffectsTests/DefaultTransitionTests.swift`; `Documentation/SwiftUI parity/Deliberate deviations
  from SwiftUI.md` (A3, A6), `Documentation/SwiftUI parity/SwiftUI compatibility guide.md` (the Animation row);
  `Documentation/SwiftUI parity/Decisions/Transition follow-ups (TRANSITIONS2).md`,
  `Documentation/SwiftUI parity/Decisions/Matched geometry and the zoom transition (O4).md` (B-O4-2).

### Badge prominence

- **Asks:** where a `.badgeProminence(_:)` written on a `List` row reaches that row's badge: around the
  `.badge(_:)`, inside it, around a padding after it, and on the list with a row's own `.standard` around its
  badge; and whether a `.badge(_:)` with a padding after it is still drawn (`badgeprom.swift`, `badgeprom.out`,
  built with `common.swift`). Counts the non-white pixels in each row's trailing 70 points: a `.standard` badge
  sits in a light grey capsule (1128 pixels), a `.decreased` one is bare grey text (157).
- **Ran:** macOS 15.8.1, Xcode's Swift 6.2.4, 2026-10-18.
- **Was:** `LISTS/probe/`.
- **Cited by:** `Sources/TUIkitFoundation/Modifiers/BadgeModifier.swift`,
  `Tests/TUIkitListsTests/BadgeProminenceTests.swift`;
  `Documentation/SwiftUI parity/Decisions/SwiftUI API completion decisions.md` (B72),
  `Documentation/SwiftUI parity/Decisions/List, table and section fixes (LISTS).md` (B-LISTS-1).

### Picker sections

- **Asks:** how a macOS menu `Picker` draws a `Section` among its options: reads back the menu of the
  `NSPopUpButton` SwiftUI makes and prints each item's kind and title (`pickersection.swift`, `pickersection.out`,
  built with `common.swift`). Each section is wrapped in separators, its header an `NSMenuItem` section header
  over its options. A section a condition empties keeps its header between its separators, over no options,
  and the collapsed control is as wide as that header needs (`emptied`: 197 points, against 74 for its one
  option alone, `baseline`).
- **Ran:** macOS 15.8.1, Xcode's Swift 6.2.4, 2026-10-18; the emptied section 2026-10-19.
- **Was:** `LISTS/probe/`.
- **Cited by:** `Sources/TUIkitPickers/Views/Picker.swift`, `Sources/TUIkitPickers/Views/_PickerOptionsReader.swift`,
  `Tests/TUIkitPickersTests/PickerSectionTitleTests.swift`;
  `Documentation/SwiftUI parity/SwiftUI compatibility guide.md` (§1, Pickers).

- **Also asks** (`ideal-placed.swift`, `ideal-placed.out`): a frame with an ideal width and no maximum round a
  5-wide box, under `.fixedSize()`, as each container places it. A row (`HStack`, `HStackLayout`), a stack of one
  view, `.padding`, `.border` and a background's base pass the unspecified width on (the frame is its ideal, 10);
  a column or a `ZStack` of several, `VStackLayout`, `ZStackLayout`, a `Grid` and an overlay's layer offer it a
  width as they place it (its content's, 5). Ran 2026-10-19, macOS 15.8.1, with Xcode's `swiftc`; cited by
  `EnvironmentValues.offeredNoWidth` (`ContainerAxisEnvironment.swift`) and
  `Tests/TUIkitFoundationTests/FrameIdealOfferedNothingTests.swift`.

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
  moves the control on from where it would be. A hidden label takes no part in the column.
- **Ran:** macOS 15.8.1, SwiftUI 6.5.4, Xcode's Swift 6.2.4; `modified.swift` 2026-10-14, `rows.swift` 2026-10-19.
- **Was:** `PROBES-1014/labeledcontent/` (`p3-modified-rows.swift`) and `FORMS/probes/` (`p4-form-rows.swift`).
- **Cited by:** `Sources/TUIkitForms/Views/FormContentExtraction.swift`,
  `Sources/TUIkitFoundation/Views/FormRowRewrapping.swift` and the modifiers' conformances to it (in
  `LifecycleModifier.swift`, `OnChangeModifier.swift`, `GestureModifier.swift`, `KeyboardShortcutModifier.swift`,
  `ContextMenuModifier.swift`, `OverlayModifier.swift` and beside them), `Tests/TUIkitIntegrationTests/FormModifiedRowTests.swift`;
  `Documentation/SwiftUI parity/SwiftUI compatibility guide.md` (Containers, `Form`).
