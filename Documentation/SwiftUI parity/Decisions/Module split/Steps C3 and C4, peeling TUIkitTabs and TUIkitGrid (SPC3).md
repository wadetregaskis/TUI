# Completing the SwiftUI API: decisions from lane SPC3

*Lane SPC3 took steps C3 and C4 of the module split
([`Module split plan, revision 4`](<../../../Historical/Module split plan, revision 4 (2026-10-07).md>),
§5), 2026-10-10: the third and fourth PEELS, the last two of the Lists group.
`Sources/TUIkitTabs` left the Lists group of step B6 for a target of its own,
TUIkitTabs, built on TUIkitFoundation and TUIkitLists, and then
`Sources/TUIkitGrid` for TUIkitGrid, built on TUIkitFoundation alone; the
residual TUIkitLists compiles the lists alone, an ordinary target, and depends
on neither new module. TUIkitColorPicker depends on TUIkitTabs in place of
TUIkitLists. The steps changed no public API: the umbrella re-exports both new
modules, so `import TUIkit` gives an app what it gave before. This file holds
the judgement calls the steps reached that the plan did not already settle, in
the format of
[`SwiftUI API completion decisions.md`](<../SwiftUI API completion decisions.md>):*

- **A-SPC3-n — needs your decision.** Nothing has shipped for these.
- **B-SPC3-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPC3-n — declined.** With the reason.

## What an app can see

Not judgement calls: the plan (§5, row C9a) lists these for the release notes,
and C9a writes them. They are recorded here because these steps made them. Each
name below was `TUIkitLists`' from step B6, `TUIkitFoundation`'s after step
B1, and `TUIkit`'s in v0.6.0.

- **Reflected names.** `String(reflecting:)`, `dump` and the debugger name the
  new modules: `TUIkitTabs.TabView<…>`, `TUIkitTabs.TabViewCustomization`,
  `TUIkitTabs.TabBarPlacement`; `TUIkitGrid.Grid<…>`, `TUIkitGrid.GridItem`,
  `TUIkitGrid.GridItem.Size`. They read `TUIkitLists.` from step B6 until these
  steps (decisions SPB6, "What an app can see", said they would change at C3
  and C4), so a release that ships both should give the new names.
  `UmbrellaQualifiedNameTests` pins them. The lists' names are unchanged
  (`TUIkitLists.EditMode`, `TUIkitLists.SidebarListStyle`).
- **Saved state is unaffected.** The two directories' one `Codable` type,
  `TabViewCustomization`, encodes the stated sidebar visibilities by tab
  identifier, each section's tab order and the section order, and no type name
  (`TabViewCustomization.swift`, `encode(to:)`), so a customization an app saved
  through `@SceneStorage` or `@AppStorage` decodes as before. No declaration of
  either directory is something a `NavigationPath` stores by name (checked by
  grep, 2026-10-10: no `_mangledTypeName`, `String(reflecting:)` or
  `String(describing:)` of a type in either directory).
- **The bundle is unchanged.** Both directories hold Swift files only, so the
  bundle is still `TUIkit_TUIkitStrings` (decisions SPB2).
- **The documentation lists each module's modifiers on `View`, on that
  module's own types, and on the types of a module that re-exports it.**
  Grid's and `LazyVGrid`'s pages no longer list TUIkitLists' `listStyle`,
  `listRowSeparator`, `selectionDisabled` or `sectionActions`, and `List`'s
  lists no `tabViewStyle`; `TabView`'s and `Table`'s still list the lists'
  modifiers (TUIkitTabs and TUIkitTables re-export TUIkitLists), and
  `View`'s lists them all (checked in the strict docs build's archive,
  2026-10-10). Member pages: `List` 358 -> 344, `Grid` 320 -> 290, `TabView`
  317 -> 313, against step C2's archive; the archive has 46,581 pages
  against its 46,817. No doc link had resolved only through such a copy: the
  strict build reports nothing.
- **`import TUIkitTabs` brings lists too**, once per-module products ship: it
  re-exports TUIkitLists, which a sidebar tab view lists its tabs in.
  **`import TUIkitGrid` brings TUIkitFoundation and nothing of the lists'.**
  **`import TUIkitLists` no longer brings tab views or grids**, and
  `import TUIkitColorPicker` brings TUIkitLists through TUIkitTabs. Under the
  umbrella, which is the only product today, nothing changes.
- **No other module gained an edge.** No file of TUIkitLists, TUIkitTables or
  any other module names a declaration of either directory but
  TUIkitColorPicker's of the tabs' (the crossing reports after each peel: 0
  sites), and no grid file names one of TUIkitLists'.

## B. Shipped

### B-SPC3-1. A sidebar tab view's list is built in TUIkitLists, not by the tab view

*Sources/TUIkitLists/Views/SidebarSectionList.swift, Sources/TUIkitTabs/Views/TabViewSidebar.swift — no API*

A `.sidebarAdaptable` tab view lists its tabs in a `.sidebar` `List`, one
section per run of tabs, each with its `TabSection`'s actions through
`sectionActions(content:)`. That modifier's `some View` names
`_SectionActionsView`, internal to TUIkitLists, so once the tab views were a
module of their own the list's content asked the runtime for that type's
conformance on every evaluation of the sidebar (CONTRIBUTING.md, "Crossing a
module boundary"; seen in the carve's release Stress, and flagged by the
crossing predictor before it).

**Shipped:** TUIkitLists builds the list: `_SidebarSectionList`, a `package`
view generic over the row's type, takes the sections (header, actions, rows by
place), the selection by place and the row, and applies the `.sidebar` style;
the tab view keeps each row's label, badge, spring loading and interactions,
`.textSelection(.disabled)` and Shift+F10. Nothing draws differently. The lookup
is gone; the list's body runs unspecialised in TUIkitLists (it cannot name the
tab view's row type), about a dozen generic calls into TUIkitFoundation and
TUIkitView per evaluation through metadata the runtime keeps, unmeasured against
the lookup. The list sits one level deeper in the view identity.

**The other version:** keep the list in TUIkitTabs and give it each section
through a `package` wrapper in TUIkitLists that holds the section with its
actions and forwards the list's section protocols (`SectionPartsProviding`,
`SectionRowExtractor`, and `ChildViewProvider` for a section outside a list)
with the identity step its body adds. The list stays specialised in the tab
view's module, at one generic call per section. Price: about 40 lines that
duplicate what `_SectionActionsView` answers, and every protocol a list asks a
section must be forwarded and kept so, or a sidebar section silently draws as a
row. No Stress scenario has a sidebar tab view, so neither is measured; the
coordinator's A/B cannot see the difference.

### B-SPC3-2. Of plan tier 2's step-C3 callees, only `selectionDisabled(_:)` is annotated

*Sources/TUIkitLists/Extensions/View+SelectionDisabled.swift, Modifiers/SelectionDisabledModifier.swift — no API*

The A1′ re-cut (tiers-A1p) lists six tier-2 callees that first cross at C3:
`EnvironmentValues.liftedSurface`, `List.init(selection:content:)`,
`listStyle(_:)`, `sectionActions(content:)`, `ListStyle.sidebar` and
`selectionDisabled(_:)`. The coordinator's rule for this step: annotate only
what the release binary shows called on a per-frame path.

**Shipped:** after B-SPC3-1 four of them are TUIkitLists' own calls and do not
cross. `selectionDisabled(_:)` did, once for every row a sidebar lists on every
evaluation, unspecialised (inlined in the base and premod): it is `@inlinable`,
with `SelectionDisabledModifier`'s memberwise initializer `@inlinable` and its
two fields `@usableFromInline`; its result type was public already, and the
binary shows the call gone. `liftedSurface`, three calls a tab view's draw,
stays a plain `package` getter: premod called it out of line as well, so the
peel changed nothing that runs.

**The fuller version:** `liftedSurface` `@inlinable` too, which would make a
tab view's draw cheaper than premod's by three calls. Price: TUIkitView's
`surfaceBackground` accessor and its environment key `@usableFromInline` (or
`@inlinable package`), state no other module needs to see. Not done: nothing
regressed there.

## Not done here

- **Grid's crossings into TUIkitFoundation.** Step C4 adds none: a grid's calls
  into TUIkitFoundation have crossed a module boundary since step B6 carved the
  Lists group. The crossing report lists them (per cell: `CellRect`'s fields,
  stored; the lattice's alignment offsets; `LayoutSubview.sizeThatFits(_:)`,
  tier 2 at B6), and one opaque-result hazard: `layoutValue(key:value:)`, which
  `gridCellColumns(_:)` and the other cell modifiers call. No Stress scenario
  has a grid (grep), so none is measured; they are B6's, and unchanged here.
