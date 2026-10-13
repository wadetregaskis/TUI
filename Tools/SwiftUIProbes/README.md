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
  `Tests/TUIkitTests/DynamicPropertyTests.swift`, `Tests/TUIkitTests/ObservableInvalidationScopeTests.swift`. The
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
  `Sources/TUIkitView/State/State.swift`; `Tests/TUIkitTests/DynamicPropertyStateKeyTests.swift` and the other
  `DynamicProperty*Tests.swift` files, `Tests/TUIkitTests/StateSharedValueTests.swift`;
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
  `Tests/TUIkitTests/DynamicPropertyStateKeyTests.swift`;
  `Documentation/SwiftUI parity/Decisions/State keys inside a DynamicProperty (SKEY).md`.

### Alignment guides

- **Asks:** whether an explicit alignment guide's value is used as given or clamped to the view's own size, in
  `VStack` and `HStack` for every alignment (`guide.swift`, `guide.out`); then the same question for `ZStack`,
  `LazyVStack`, a single child's `.frame` and `.overlay` placement, a stack inside a frame, and a stack whose
  region a flexible child sets (`guide2.swift` to `guide6.swift`, each with its `.out`; all share
  `guide.swift`'s harness).
- **Also:** `GuideProbeTests.swift`, a Swift Testing suite that records TUIkit's placements for the same matrix
  into `tuikit.out` (copy it into `Tests/TUIkitTests` to run it; it was written against TUIkit at 45e9a1f7a and
  has not been re-checked against today's); `check.py`, which fits SwiftUI's rule and TUIkit's then rule to the
  two outputs (`python3 check.py`: 135 rows each, no mismatch) and says which of TUIkit's two rules made each of
  the 72 differing rows differ. `tuikit.out` records TUIkit before the fix this probe led to.
- **Ran:** macOS 15.8.1, SwiftUI 6.5.4, Swift 6.2.4, 2026-10-11.
- **Was:** `GUIDE/probe/` and `GUIDE/probe2/` (and `GUIDE/tuikit.out`).
- **Cited by:** `Tests/TUIkitTests/AlignmentGuideParityTests.swift`,
  `Tests/TUIkitTests/AlignmentGuideContainerParityTests.swift`;
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
  `common.swift`, whose `Counter` layout and `probe(_:)` modifier print what a container saw.
- **Ran:** macOS 15.8, 2026-10-04 and 2026-10-05. `cv.swift`, `lv.swift` and `z.swift` kept no output.
- **Was:** `D1S/probe/`, and `D1S/probe2/` for the second round.
- **Cited by:** `Sources/TUIkitView/Core/AnyViewMembers.swift`, `Sources/TUIkitView/Rendering/CompositeMembers.swift`,
  `Sources/TUIkitForms/Views/FormContentExtraction.swift`, `Sources/TUIkitFoundation/Rendering/MenuSections.swift`,
  `Sources/TUIkitLists/Views/ListRowEditOwner.swift`; `Tests/TUIkitTests/AnyViewMembersTests.swift`,
  `Tests/TUIkitTests/SubviewLayoutTraitsTests.swift`, `Tests/TUIkitCollectionTests/ForEachRowMembersTests.swift`,
  `Tests/TUIkitCollectionTests/ForEachRowVaryingMembersTests.swift`,
  `Tests/TUIkitCollectionTests/SectionPartsTests.swift`, `Tests/TUIkitCollectionTests/CompositeMembersTests.swift`,
  `Tests/TUIkitCollectionTests/ListMultiViewRowEditingTests.swift`,
  `Tests/TUIkitControlTests/FormWrappedSectionTests.swift`, `Tests/TUIkitAppTests/MenuSectionTests.swift`;
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
- **Cited by:** `Tests/TUIkitCollectionTests/PinnedRowSectionTests.swift`,
  `Tests/TUIkitCollectionTests/LazyGridSectionTests.swift`; wave 10b's entries in
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
  `Tests/TUIkitTests/SwiftUIKeySpellingTests.swift`; `Sources/TUIkit/TUIkit.docc/Articles/Localization.md`;
  `Documentation/SwiftUI parity/SwiftUI compatibility guide.md`.

### Animation curves, springs and keyframes

- **Asks:** what SwiftUI's animation types compute, with no view: whether each transition has motion
  (`p1.swift`); how an `Animation` describes and mirrors itself (`p2.swift`); each `UnitCurve`'s values and
  velocities (`p3.swift`); a `Spring`'s parameters, values and velocities by each way of making one (`p4.swift`,
  `p5.swift`); a `KeyframeTimeline`'s values over time (`p6.swift`, `p7.swift`); and the environment's default
  `contentTransition` and how `ContentTransition`s compare (`p8.swift`). Each is a program alone (`@main`, no
  shared file); the numbers print to six places.
- **Ran:** against the macOS 26.2 SDK, on the development Mac, 2026-10-03. `p1`, `p2`, `p3` and `p8` kept no
  output; their results are in wave 12's decisions.
- **Was:** `w12/probe/`.
- **Cited by:** `Sources/TUIkitView/Animation/KeyframeCurve.swift`; `Tests/TUIkitTests/KeyframeTimelineTests.swift`,
  `Tests/TUIkitTests/SpringTests.swift`, `Tests/TUIkitTests/UnitCurveTests.swift`; wave 12's entries in
  `Documentation/SwiftUI parity/Decisions/SwiftUI API completion decisions.md`.

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
  `Tests/TUIkitCollectionTests/ScrollWindowHoldTests.swift`; `Documentation/Layout and scrolling/Scroll
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
- **Cited by:** `Sources/TUIkitFoundation/Modifiers/FrameModifier.swift`; `Tests/TUIkitTests/PlacementOverflowTests.swift`;
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
- **Cited by:** `Sources/TUIkitForms/Styles/LabeledContentStyle.swift`; `Tests/TUIkitControlTests/LabeledContentTests.swift`,
  `Tests/TUIkitControlTests/FormTests.swift`; `Documentation/SwiftUI parity/SwiftUI compatibility guide.md`.
