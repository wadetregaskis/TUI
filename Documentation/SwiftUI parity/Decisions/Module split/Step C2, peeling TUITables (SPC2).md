# Completing the SwiftUI API: decisions from lane SPC2

*Lane SPC2 took step C2 of the module split
([`Module split plan, revision 4`](<../../../Historical/Module split plan, revision 4 (2026-10-07).md>),
§5), 2026-10-09: the second PEEL, after set T. `Sources/TUITables` left the
Lists group of step B6 for a target of its own, TUITables, built on
TUIFoundation and TUILists; the residual TUILists compiles lists, tabs
and grids, on TUIFoundation alone, and does not depend on the new module.
The step changed no public API: the umbrella re-exports TUITables beside
TUILists, so `import TUI` gives an app what it gave before. This file
holds the judgement calls the step reached that the plan did not already
settle, in the format of
[`SwiftUI API completion decisions.md`](<../SwiftUI API completion decisions.md>):*

- **A-SPC2-n — needs your decision.** Nothing has shipped for these.
- **B-SPC2-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPC2-n — declined.** With the reason.

## What an app can see

Not judgement calls: the plan (§5, row C9a) lists these for the release notes,
and C9a writes them. They are recorded here because this step made them. Each
name below was `TUILists`' from step B6, `TUIFoundation`'s after step
B1, and `TUI`'s in v0.6.0.

- **Reflected names.** `String(reflecting:)`, `dump` and the debugger name a
  table type's new module: `TUITables.Table<…>`,
  `TUITables.TableColumnCustomizationBehavior`. They read `TUILists.`
  from step B6 until this step (decisions SPB6, "What an app can see", said
  they would change at C2), so a release that ships both steps should give
  the C2 name. `UmbrellaQualifiedNameTests` pins the table and the
  customization behaviour. The lists', tabs' and grids' names are unchanged
  (`TUILists.EditMode`, `TUILists.TabViewCustomization`,
  `TUILists.GridItem`).
- **Saved state is unaffected.** The directory's one `Codable` type,
  `TableColumnCustomization`, encodes the columns' stated visibilities by
  identifier, their order and their widths, and no type name
  (`TableColumnCustomization.swift`, `encode(to:)`), so a customization an app
  saved through `@SceneStorage` or `@AppStorage` decodes as before. No
  declaration of the directory is something a `NavigationPath` stores by name,
  and nothing in the directory saves a type's name (checked by grep,
  2026-10-09, again 2026-10-10: no `_mangledTypeName` or
  `String(reflecting:)`; the four `"\(Self.self)"` interpolations, which are
  `String(describing:)` and give the unqualified name, label a fit-width memo
  and a served row for the render cache's verifier, `Table.swift`, and two
  assertion messages, `TableColumnContent.swift` and `TableRowContent.swift`,
  none of them saved).
- **The bundle is unchanged.** The directory holds Swift files only, so the
  bundle is still `TUI_TUIStrings` (decisions SPB2).
- **The documentation lists each module's modifiers on `View`, on that
  module's own types, and on those of the modules built on it, not on a
  sibling's.** `symbolgraph-extract` copies a protocol
  extension's members onto the conforming types of its own module only
  (decisions SPC1), and lists and tables are two modules now: `List`'s,
  `TabView`'s and `Grid`'s pages list neither `tableStyle` nor
  `tableColumnHeaders` among their default implementations, while `View`'s
  lists both (checked in the strict docs build's archive, 2026-10-09).
  `Table`'s page still lists TUILists' `listStyle` and
  `listRowSeparator`. "Its own module" qualifies the conforming types, not the
  extension: TUITables imports TUILists (and re-exports it, below), so
  TUILists' `View` extension is loaded when TUITables' graph is
  extracted, and its members are copied onto `Table`, a type of TUITables'
  own (`Table/listStyle(_:)` is in `TUITables.symbols.json`, extracted
  with Xcode's `swift-symbolgraph-extract`, 2026-10-10). TUILists loads
  nothing of the tables', so its types get no copy of theirs. Whether an
  import that does not re-export would do the same is unmeasured. The archive
  has 46,817 pages against step C1's 46,868.
  No doc link had resolved only through such a copy: the strict build
  reports nothing.
- **`import TUITables` brings lists too**, once per-module products ship:
  it re-exports TUILists (plan §4: "Tables re-exports Lists"), whose row
  engine a table runs on. **`import TUILists` no longer brings tables.**
  Under the umbrella, which is the only product today, nothing changes.
- **No other module gained an edge.** TUIColorPicker and every other
  carved module name no declaration of the directory (the pre-peel index: 0
  references), and no file of TUILists names one (the post-peel crossing
  report: 0 sites).

## B. Shipped

### B-SPC2-1. Set T: the row memo crosses with its bodies; the handler's members a table calls once a frame stay out of line

*Sources/TUILists/Views/TableRowMemo.swift, Focus/ItemListHandler+Reorder.swift — no API*

Plan §5 and the A1′ re-cut (tiers-A1p) name set T: nine callees a table calls
in TUILists, `@inlinable package`, with the state their bodies touch
`@usableFromInline`. Five of them are `ItemListHandler`'s own members:
`publishRowBands(_:)`, `isSelected(at:)`, `id(at:)`,
`drawnBands(_:slide:rowsTop:lineCount:)` and `reorderRemovedRows`.

**Shipped:**

- The row memo's per-row members are `@inlinable package` on
  `@usableFromInline` structs: `TableRowMemoStore.keep(_:for:)`, both
  `TableRowMemoLine.answers`, which set T names, and on the same path
  `entry(for:)`, `refresh(row:for:)`, the line's initializer,
  `drawn(striped:)` and `keep(_:striped:)`, and an explicit
  `TableRowDrawnLine` initializer. The store is reached through
  `ItemListHandler.tableRowMemo`, which stays a stored property, changed in
  place (B-SPC2-2).
- `reorderDrawnRows(_:)` takes a `Range<Int>`, a concrete entry beside the
  generic `reorderDrawnRows(_:excluding:)` that `List` calls with an array:
  the generic one, called from another module with the caller's own type,
  is its unspecialised entry (crossing_hazards' HAZARD-GENERIC; SPB6's R1).
- The handler's five stay out of line, `package`: a table calls each once a
  frame (`isSelected(at:)` and `id(at:)` once a frame or per event; the
  per-row selection test is `drawsSelected(at:)`, which runs both inside
  TUILists).

**The other version:** the five `@inlinable`. **Price:** an `@inlinable`
member of a type that is neither public nor `@usableFromInline` gets no body
in another module, and a `@usableFromInline` class must make every member that
witnesses one of its protocols' requirements `@usableFromInline` too: the
build asked for at least 25 (`Focusable`, `ScrollableOffsetState`), among them
stored properties whose accesses are statically enforced (`focusID`,
`canBeFocused`, `scrollOffset`, `viewportHeight`), each of which would keep a
run-time exclusivity check from then on, or would need private storage under
an accessor. And the bodies read handler state that CONTRIBUTING's rule keeps
behind out-of-line accessors (`itemCount`, `idAt`, `visibleRowBands`,
`externalDropSlot`), so inlined they would make more calls than the one they
save. Worth revisiting only if the A/B finds the five.

### B-SPC2-2. Four of the handler's stored properties are `package` and stored; 42 others are private storage under accessors

*Sources/TUILists/Focus/ItemListHandler.swift, Views/RowContextMenuHost.swift, Views/RowReorderPayload.swift — no API*

The peel widens what a table names in TUILists, and since a `package` class
must make each member that witnesses one of its protocols' requirements as
visible, the handler's witnesses too. CONTRIBUTING.md ("Crossing a module
boundary") keeps a class's stored property private, under a `package`
accessor, unless the binary shows every access to it dynamically enforced
already.

**Shipped:** 42 private storages under accessors (39 of the handler's, the
reorder grab point's `x` and `y`, the row menu state's `target`), and four of
the handler's `package` and stored, each with its evidence in its doc
comment: `tableRowMemo` and `returningRows`, which a table reads for every row
it draws (the first changed in place: under a getter and setter each change
would copy the store's dictionary), and `reorder` and `outlineActivation`,
whose checks stay whichever way they are written. Measured, in two release
binaries: widening all fourteen dynamically enforced properties stored gave
each a getter, setter and `modify` with a check of its own, for its property
descriptor (39 static `swift_beginAccess` sites that nothing calls); as
private storage under an accessor, ten of the twelve others lost every check,
which also takes checks off `List`'s and `Table`'s row composition; `reorder`
and `outlineActivation` kept theirs, in their accessors, which TUILists
then called where it had read them in place.

**The other version:** every one private storage under an accessor, as the
rule's letter has it. **Price:** a table's per-row memo test and keep through
a getter and setter copies the store's dictionary on each change (so through
seven forwarding methods on the handler instead, or a `_modify` accessor,
whose coroutine frame another module allocates on the heap, SPB6's R3), and
`returningRows` and `reorder` become calls where both modules read them in
place. Or every dynamically enforced one stored: +27 static sites of
accessors nothing calls, and the checks the ten others would keep.

## C. Declined

None.

## For the coordinator (not decisions)

- **peel.py (C2):** the known `tablecolumn` page-guard addition (undone by
  hand: `table` covers the directory); a false-positive warning that
  `ItemListHandler.swift` "seems to name TUITables's lastRow" (a local
  name; the build has no such edge); four `@testable import TUITables`
  it could not see textually (DrawnNothingPopupGestureTests,
  TableColumnGestureTests, TableColumnLineLimitTests, TableStyleTests, which
  reach `subscript(width:)`, `lineLimit` and a style's `Configuration`); and
  its CONTRIBUTING row draft says "peeled off" where C1's row says "peeled
  out of".
