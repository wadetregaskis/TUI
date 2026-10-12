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
  (`weak.out`), `passmod.swift` (`passmod.out`), `notes.md`.
- **Ran:** macOS 15.8.1, SwiftUI 6.5.4, 2026-10-10.
- **Was:** `DYNP/optional/`.
- **Cited by:** `Sources/TUIkitView/State/DynamicProperty.swift`,
  `Sources/TUIkitView/State/NestedPropertyBinding.swift`; `Tests/TUIkitTests/DynamicPropertyStateKeyTests.swift`;
  `Documentation/SwiftUI parity/Decisions/State keys inside a DynamicProperty (SKEY).md`,
  `Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md`.

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
  survives `ForEach(subviews:)` in a `ZStack`, from the pixels (`z.swift`). All are built with `common.swift`,
  whose `Counter` layout and `probe(_:)` modifier print what a container saw.
- **Ran:** macOS 15.8, 2026-10-04. `cv.swift`, `lv.swift` and `z.swift` kept no output.
- **Was:** `D1S/probe/`.
- **Cited by:** `Sources/TUIkitView/Core/AnyViewMembers.swift`; `Tests/TUIkitTests/AnyViewMembersTests.swift`,
  `Tests/TUIkitTests/SubviewLayoutTraitsTests.swift`, `Tests/TUIkitCollectionTests/ForEachRowMembersTests.swift`,
  `Tests/TUIkitCollectionTests/ForEachRowVaryingMembersTests.swift`,
  `Tests/TUIkitCollectionTests/SectionPartsTests.swift`;
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
