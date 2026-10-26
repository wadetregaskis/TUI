# Completing the SwiftUI API: decisions from lane SPB6

*Lane SPB6 took step B6 of the module split
([`Module split plan, revision 4`](<../../../Historical/Module split plan, revision 4 (2026-10-07).md>),
§5), 2026-10-08: the carve of the Lists group, the fourth module built on
TUIFoundation rather than under it, and the second coarse group: one
target, TUILists, that compiles four planned modules' directories,
`Sources/TUILists`, `Sources/TUITables`, `Sources/TUITabs` and
`Sources/TUIGrid`, until steps C2, C3 and C4 peel the last three into
targets of their own. It changed no public API: the umbrella re-exports
TUILists beside TUIFoundation, so `import TUI` gives an app what it
gave before. This file holds the judgement calls the step reached that the
plan did not already settle, in the format of
[`SwiftUI API completion decisions.md`](<../SwiftUI API completion decisions.md>):*

- **A-SPB6-n — needs your decision.** Nothing has shipped for these.
- **B-SPB6-n — shipped the safe option.** Says what the other version would be, and its price.
- **C-SPB6-n — declined.** With the reason.

## What an app can see

Not judgement calls: the plan (§5, row C9a) lists these for the release notes,
and C9a writes them. They are recorded here because this step made them. Each
name below was `TUIFoundation`'s after step B1, and `TUI`'s in v0.6.0.

- **Reflected names.** `String(reflecting:)`, `dump` and the debugger name a
  moved type's new module: `TUILists.EditMode`,
  `TUILists.SidebarListStyle`. That includes the types of
  `Sources/TUITables`, `Sources/TUITabs` and `Sources/TUIGrid`, which
  compile into TUILists until steps C2, C3 and C4:
  `TUILists.Table<…>`, `TUILists.TableColumnCustomizationBehavior`,
  `TUILists.TabViewCustomization`, `TUILists.TabBarPlacement`,
  `TUILists.GridItem`, `TUILists.GridItem.Size`. Those names change
  again at each peel, to `TUITables.`, `TUITabs.` and `TUIGrid.`, so
  the release notes should give the peeled name for a type if its peel ships
  in the same release. `UmbrellaQualifiedNameTests` pins at least one from
  each directory.
- **Saved state is unaffected.** The four directories declare two public
  `Codable` types, `TableColumnCustomization` and `TabViewCustomization`. Each
  encodes its data under coding keys of its own, with no type name, so a
  customization an app saved (to `@AppStorage` or `@SceneStorage`, as SwiftUI
  suggests) still decodes. Neither is `Hashable`, so neither can be a value in
  a `NavigationPath`, whose saved representation is the one that stores type
  names (decisions SPB5, "Saved navigation paths").
- **The bundle is unchanged.** The four directories hold Swift files only (the
  rows', tables' and tabs' labels come from TUIStrings' tables through
  `LocalizationService`), so the bundle is still `TUI_TUIStrings`
  (decisions SPB2).
- **The documentation lists the group's modifiers on `View` and on the
  group's own types, not on TUIFoundation's.** As at step B5:
  `symbolgraph-extract` copies a protocol extension's members onto the
  conforming types of its own module only, so `Text`'s page no longer lists
  `listStyle(_:)`, `tabViewStyle(_:)` or `gridCellColumns(_:)` among its default
  implementations, while `View`'s and `List`'s and `TabView`'s pages still do
  (checked in the strict docs build's archive, 2026-10-08). The archive has
  59,764 pages against step B5's 63,396; how many of the 3,632 are such
  copies was not counted. No doc link had resolved only through one: the
  strict build reports nothing.
- **`import TUIColorPicker` brings lists, tables, tabs and grids too**, once
  per-module products ship: it re-exports TUILists, its new direct
  dependency (its panel lays its modes out in a `TabView` of `Tab`s). After C3
  it re-exports TUITabs instead, which re-exports TUILists (plan §4).
  Under the umbrella, which is the only product today, nothing changes.
- **`import TUINavigation` does not bring `List`.** TUINavigation does
  not depend on TUILists: no file of its two directories names a
  declaration of the group's four (the pre-carve index: 0 references; the
  split views take their columns as any `View`), and the plan's map has no
  such edge. An app that writes `NavigationSplitView { List … }` gets `List`
  from the umbrella today, and from `import TUILists` once per-module
  products ship.

## B. Shipped

### B-SPB6-1. `Group`'s initializers for table columns, table rows and tabs build it through a package factory

*Sources/TUIFoundation/Views/Group.swift — no API*

`Group` is TUIFoundation's, and its `let content` is set by a `fileprivate
init(grouping:)`, so that no memberwise `init(content:)` exists for a trailing
closure to bind to (`Group { … }` with `Content` unconstrained would match it
with the closure as the content). Three of its public initializers live with
the builders they take, which the group declares: `init(content:)` for
`@TableColumnBuilder`, `@TableRowBuilder` and `@TabContentBuilder`. Each
assigned `self.content` itself, which an initializer in an extension declared
in another module may not do ("'let' property 'content' may not be
initialized directly", the class step B5 met with `Button(_:action:)`).

B5 moved its initializer into the type's own file. These three cannot move:
TUIFoundation cannot see the builders. A `package init(grouping:)` would
let the trailing closure bind again, now from every module of the package.

**Shipped:** `package static func grouping(_ content:) -> Self`, which calls
the `fileprivate` initializer; the three initializers say `self =
.grouping(content())`. A static function cannot be reached by `Group { … }`.

**The other version:** a `package` initializer with a second, unlabelled
parameter no closure can fill (say `init(grouping:_: Void)`). **Price:** none
in code, but it is an initializer whose shape exists only to dodge overload
resolution, which the factory states plainly.

### B-SPB6-2. No Stress scenario for grids, and none for tab views beyond a session, is added here

*Sources/Stress — nothing shipped*

The step's brief asks for the per-row and per-cell crossings the carve
creates, the scenarios that exercise each, and a proposal where a hot crossing
has none. Two of the group's four directories have none in `Stress --bench`'s
scenario list:

- **Grids.** No scenario draws a `Grid`, `LazyVGrid` or `LazyHGrid` (checked
  by grep over Sources/Stress, 2026-10-08). The per-cell crossings
  (`GridLattice.placement` → `HorizontalAlignment.childOffset` and
  `VerticalAlignment.childOffset`; `placeSubviews` → `LayoutSubviews`'
  subscript, `LayoutSubview.place` and `sizeThatFits`) are measured by
  nothing.
- **Tab views.** Only the `notes` session (`--bench --scenario
  session/notes`) draws a `TabView`; no scenario does. Its strip assembles
  each tab's cells through `ClaimingRow`, set L and `@inlinable` since step
  A3; what crosses uninlined is one `HorizontalAlignment.childOffset` per
  strip line, and the per-frame calls of `TabView` itself.

**Shipped: nothing.** A scenario added in this lane would exist only on the
carved side of the coordinator's A/B, which compares the same scenario on
both trees.

**The other version:** a `ScenarioVariant` of `dashboard`, `grid`: the same
metric panels in a `LazyVGrid(columns: [GridItem(.adaptive(minimum: 24))])`,
and a second, `grid-fixed`, in a `Grid` of `GridRow`s (about 30 lines with
their summaries).

**Built 2026-10-19 (lane TOOLING), as a scenario of its own rather than a
`dashboard` variant:** the sweep runs each scenario's default variant only, so
`grids` takes `lazy` (the panels in an adaptive `LazyVGrid`, the default, and
what decisions B71 owes a lazy grid's cost to) and `fixed` (a `Grid` of
`GridRow`s). The sidebar tab view is `app-shapes/sidebar-tabs`. **Price:** a scenario the sweep then runs on every A/B (a
second or two), landed on main before the next carve's A/B so that both sides
have it. Worth it before step C4 peels Grid, the first step whose own A/B
would otherwise have nothing to measure.
