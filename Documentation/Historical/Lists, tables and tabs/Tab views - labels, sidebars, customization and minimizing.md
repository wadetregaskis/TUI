# Tab views: labels, sidebars, customization and minimizing

*How a tab's label is drawn, the sidebar-adaptable style, tab customization,
minimizing the tab bar, `Tab`'s image initialisers, and the forms declined.
Ids: B75, B76, B76-SELECT, B79, B96, TABBARMIN, C11, TAB-IMAGE-NAME, C16
(SA-82), A50, B-LISTS2-4, B-LISTS2-8.*

## In short

A tab's chip draws its label as text (the title after an SF Symbol's glyph).
The `.sidebarAdaptable` style draws a `.sidebar` list beside the content,
chosen with Return; customization (hidden and reordered tabs) is the app's to
change, as measured; `.automatic` minimizing shrinks a bordered or grouped tab
view to its strip in a compact size class. `Tab`'s `image:` forms ship in a
module of their own. `TabView` with plain-view content stays declined.

## How it unfolded

1. **B75, B76, B79** shipped the labels, the sidebar style and customization;
   lane LISTS2 (2026-10-19) built the sidebar's section moves (B-LISTS2-4) and
   its width (B-LISTS2-8).
2. **2026-10-04, A50:** search in a tab view deferred until a macOS 26 or 27
   pass can measure it.
3. **2026-10-23 to 24, the owner.** B76-SELECT: (b) for now, keep choosing
   with Return. TAB-IMAGE-NAME: ship the `String` forms (C11 corrected; built
   in `TUITabImages`). TABBARMIN: (b), built (B96). SA-82: decline (C16).
4. **2026-10-26, B75:** asked what SwiftUI does, the owner chose: draw a tab's
   custom label view inside its chip (variable heights allowed), keeping text
   labels' path and cost untouched. Built the same day (below).

## Where it stands

Shipped as above, a custom label view drawn whole in its chip; A50 is deferred
to the macOS 26/27 pass.

## The record

### B75. A tab's label is drawn as text

*`Tab.init(content:label:)`, `Tab.init(value:content:label:)`,
`Tab.init(role:content:label:)`, `Tab.init(value:role:content:label:)`,
`DefaultTabLabel`*

The strip draws each tab as a chip (`▐ title ▌`, or a folder tab), in the
strip's own ink — the active one breathing while the strip has the focus —
on the strip's own field. A label view of the app's own would bring its own
colours and layout into that.

**Shipped:** the default label is the title, after the SF Symbol's glyph
where the terminal can draw it (`Label(_:systemImage:)`'s rule). A label of
the app's own is rendered as a measure — it registers nothing — under an
identity of its tab's, and its first line is taken without its colours: the
strip draws the label's text, in the strip's ink.

**The fuller version** draws the label view itself into the chip: rendered at
the chip's height with the strip's ink as its foreground style and the chip's
fill as its background, spliced in finished, its own runs and claims carried.
The breath would have to repaint it per frame, which the strip's run does by
redrawing the chip's text today. Half a day, most of it the breath and the
folder style's walls.

**Built (owner, 2026-10-26: the fuller version, variable heights allowed;
text labels keep their path and cost):** the label is measured once the tab
view has a context and drawn whole in its chip, centred in a row as tall as
the row's tallest label; a text label sits on that row's middle line, and a
badge beside the label's middle line. Where the label states no colour it is
drawn in the strip's ink, bold on the active tab; its own colours stay. The
breath does not render the label again per step: the label is drawn once in
the breath's resting ink, and each frame rewrites that ink
(`SGRColorRewrite`), one run per line. So a colour of the label's own that is
exactly the resting ink breathes with it. A folder tab's walls run down every
line, and its click region covers its tops, its lines and, on the bottom row,
the border under them. A label is drawn, not used: it registers nothing, as
the chip is the control.

**For a future reader:** a strip with no label of the app's own draws the
bytes it drew before; `TabCustomLabelTests` pins the rest.

### B76. The sidebar style: a list beside the content, chosen with Return

*`SidebarAdaptableTabViewStyle`, `TabViewStyle.sidebarAdaptable`,
`TabBarPlacement` (all members), `EnvironmentValues.tabBarPlacement`,
`EnvironmentValues.isTabBarShowingSections`, `View.tabViewSidebarHeader(content:)`,
`View.tabViewSidebarFooter(content:)`, `View.tabViewSidebarBottomBar(content:)`*

Measured on macOS 15.8: `.sidebarAdaptable` is a split view whose leading
pane is an outline list of the tabs — a `TabSection`'s header above its tabs,
a badge at a row's trailing edge — and the selected tab's content beside it.
Tab content reads `\.tabBarPlacement` as `.sidebar` there and
`\.isTabBarShowingSections` as true; under every other style `.topBar` and
false.

**Shipped:** the sidebar is a `.sidebar`-style `List` hugging its widest row,
a rule, then the content, sized and kept as a strip's content is. Its
sections, badges and disabled rows are the list's own, and a `Label` tab
label's icon takes the list item tint, as a sidebar list's does. The header, footer and bottom bar sit above
and below the list. The two environment values report as measured.

Where it differs:

- **Choosing a tab.** The arrow keys move the list's cursor, and Return,
  Space or a click choose the tab — TUI's list convention. A macOS sidebar
  selects as the cursor moves. Following the cursor needs a list mode that
  selects as it moves (a `List` option of TUI's own, or the sidebar style
  watching the cursor), about two hours; whether every keystroke should swap
  the content beside it is the question.
- **The header and footer stay put.** SwiftUI's header and footer scroll with
  the tabs; here they are fixed above and below the list, and only the tabs
  scroll. Moving them into the list as a first and last row is an hour, but a
  header that is a row is a row the cursor must step over. **Moved
  (2026-10-19, lane LISTS2):** they are the sidebar list's first and last
  rows and scroll with the tabs; the selection names the tab rows by a type
  their ordinals do not cast into, so the cursor steps over both, and a
  control in either is a Tab stop. The bottom bar stays put below the list,
  as SwiftUI's does.
- **Sections are not collapsible.** macOS lets the user fold a sidebar
  section. The list's `Section(isExpanded:)` does it (tried on this branch),
  but a list draws its section headers before it registers its own focus
  stop, so each fold joins the focus ring ahead of the tabs and the first
  fold, not the tab list, takes the initial focus. The same order holds for
  any control in a list's section header — a `Section(isExpanded:)` fold, a
  `.sectionActions` button — in any list. Registering the list's own stop
  before its eager rows are drawn fixes both; about two hours, with the
  focus-order tests that pin the rest. The sidebar folds once that is in.
  **The focus order is fixed (2026-10-14):** a list reserves its own place in
  the focus ring before it extracts its rows (`_ListCore.registerOwnFocusStop`,
  `FocusManager.reservePlace`), so it comes ahead of its headers' folds and
  actions — and of the controls in its hand-written rows, as it already came
  ahead of a loop's — and takes the first focus (`SectionIsExpandedTests`).
  **The sidebar folds (2026-10-14):** each `TabSection`'s header is a fold, the
  folded set the sidebar's own state (`_SidebarSectionList`;
  `TabViewSidebarTests`).

### B79. Tab view customization is the app's to change; no gesture changes it

*`TabViewCustomization` (all members, `SectionCustomization`,
`TabCustomization`), `View.tabViewCustomization(_:)`,
`TabContent.customizationID(_:)`, `.defaultVisibility(_:for:)`,
`.customizationBehavior(_:for:)`, `AdaptableTabBarPlacement`,
`TabCustomizationBehavior`, `AppStorage`/`SceneStorage`
`init(wrappedValue:_:)` for a customization*

Measured on macOS 15.8 (offscreen `NSHostingView`, a customization bound): a
tab whose `[tab:].sidebarVisibility` is `.hidden` leaves the
`.sidebarAdaptable` sidebar and stays in a `.tabBarOnly` tab bar;
`.defaultVisibility(.hidden, for: .tabBar)` and `for: .automatic` leave the
tab in both. macOS lets the user drag sections to reorder them and offers no
visibility control of its own ("a custom experience should be provided",
says the documentation). Its encoding is private (a UUID, `perTabState`,
`perSectionState`).

**Shipped:** all of it, as measured, with the shape of table column customization (B45, shipped 2026-10-06): a hidden tab leaves
the sidebar and not a strip; a stated tab order (per section) and section
order are applied to the sidebar, the identified items taking the slots
identified items had; `Codable` in TUI's own encoding; persisted through
`@AppStorage`/`@SceneStorage` with no default written. The binding is read,
never written: the environment carries the value, not the binding, so the
render memos below the tab view stay on.

Where it differs:

- **No gesture reorders sections.** macOS drags them; a keyboard pair to move
  the focused section up and down needs a notion of a focused section the
  sidebar list does not have — about a day, with a decision on whether the
  list's cursor row or its section header is the thing moved. So a stated
  order comes only from the app or a decoded value. **Built (2026-10-19, lane
  LISTS2), option 1:** the thing moved is the section, through its header's
  fold (a focus stop since 2026-10-14): with it focused, the list's row-move
  chords move the section among the identified sections — Ctrl-R picks it up,
  the arrows, Home and End move it, Return puts it down and Escape puts it
  back, as the focus leaving its header does; Ctrl/Option with an arrow moves
  it at once — and the pointer drags a
  header onto another's, the section taking that one's place. A press
  released without moving still folds it. The new order is written through
  the binding once the move is put down. The environment carries the bound
  value with its binding, compared by the value alone, so the memos below the
  tab view stay on. A/B owed: the tabs scenarios.
- **`.defaultVisibility(_:for:)` and `.customizationBehavior(_:for:)` do
  nothing**, as on macOS: the placement the first acts on (`.sidebar`) and the
  behaviors the second restricts (`.reorderable`, `.disabled`) are not
  macOS's, so no macOS source can ask either for anything.

### B96. `tabBarMinimizeBehavior(.automatic)` minimizes the folder tabs in a compact size class

*`View.tabBarMinimizeBehavior(_:)`, `TabBarMinimizeBehavior` (`.automatic`)*

macOS has one behavior, `.automatic`, which Apple documents as minimizing the
tab bar when the window is short of room (`.never`, `.onScrollDown` and
`.onScrollUp` are iOS's alone). So the API is not inert on macOS, and O8 does
not refuse it.

**Shipped 2026-10-24** (owner, TABBARMIN, option b): under `.automatic`, the
default, a `.bordered` or `.grouped` tab view in a horizontally compact size
class draws the compact strip instead of its folder tabs over a box, as a
`.sidebarAdaptable` one draws the strip instead of its sidebar (B3). The
default strip, `.automatic`, `.tabBarOnly` and `.compact`, is already the
minimal bar. TUI's size classes are `.regular` unless the app writes one,
so no default changes. The modifier writes the behavior into the environment,
where the tab view reads it; with one value it changes nothing yet, and a
second (a TUI-specific `.never`, or iOS's when they reach macOS) would be read
there.

**The alternatives priced at the ruling:** minimizing below a size threshold
by default, as macOS does when a window is short of room (half a day to a day,
and a default that changes, with a threshold to judge); or refusing it with a
true reason (15 minutes). A vertically compact class does not minimize the
bar, though the folder tabs cost two rows: `.sidebarAdaptable`'s collapse
follows the horizontal class, and the ruling extends that one.

### C11. `Tab`'s `image:` initialisers: declined on a wrong reason, shipped since in a module of their own

*`Tab.init(_:image:content:)`, `Tab.init(_:image:role:content:)`,
`Tab.init(_:image:value:content:)`, `Tab.init(_:image:value:role:content:)`*

This entry declined them on the ground that the `image:` spelling names an
`ImageResource` from an asset catalogue, which a terminal app's build does not
have — the reason `Button`, `Toggle`, `Picker`, `Menu` and `ControlGroup` give
in `parity-map.json` — and added `Tab.init(_:image:*` to that family. The
ground was wrong. The installed SDK declares every `Tab` `image:` parameter as
a `String` (`SwiftUI.swiftinterface`, the `extension SwiftUI.Tab : TabContent`
and `where Value == Never` initialisers); `Label(_:image:)` with a name
already ships and draws a 2×1-cell picture (refusal review P12,
`ImageNameInitializers.swift`). The `systemImage:` forms are implemented.

**Corrected 2026-10-23** (owner, TAB-IMAGE-NAME, option a): the `String` forms
are to ship as `Label`'s do — an extension in TUIBitmaps (TUITabs does
not depend on it) that finds the name as `Image(_:bundle:)` does. The picture
shows in the sidebar list; the strip's chips show only the title, as they do
for a symbol the terminal cannot draw (B75 would draw the picture there too).
`Tab.init(_:image:*` is no longer in the map's `ImageResource` family. The
compatibility guide and `Tab`'s own doc comment no longer give the
asset-catalogue reason.

**Placed 2026-10-24** (owner, TAB-IMAGE-NAME follow-up, option 2). Built in
TUIBitmaps as ruled (branch `lane-tabs-image`, f166bc31a), they made it
depend on TUITabs, and through it TUILists and TUIPresentation, so an
app that showed an image paid for tabs: an app on `TUIApp` and
`TUIBitmaps` with no tab view grew 8,163,440 → 9,054,784 B (+10.9%), one on
`TUIBitmaps` alone 6,771,792 → 7,680,736 B (+13.4%), measured 2026-10-24
(Xcode's Swift 6.2.4, release, default traits, `strip`). The other way round,
TUITabs on TUIBitmaps, would put the image decoders under
TUIColorPicker, whose panel is a `TabView` and whose module-map `lower`
list forbids TUIImage. So they live in **TUITabImages**, a module and
library product of their own built on TUIBitmaps and TUITabs, which it
re-exports, and which the umbrella re-exports: an app pays for them only when
it uses both, and an app on module products lists `TUITabImages` to get
them.

**Shipped 2026-10-24** (lane TABIMG): the `String` forms, in
`Sources/TUITabImages/Tab+ImageName.swift` — SwiftUI's, with `role:`
defaulted as TUI's `systemImage:` forms have it, and without the
`LocalizedStringResource` titles, which no `Tab` form takes here. The name is
found as `Image(_:bundle:)` finds it; a `.sidebarAdaptable` sidebar's row
draws the picture in two cells before the title, and its row memo compares
the picture's source; a strip's chip draws the title alone. TUITabs carries
the picture (`DefaultTabLabel`'s, an `Image`, TUIFoundation's type) and
draws it, and opens the two initialisers the new module calls at `package`
access; it needs nothing of TUIBitmaps. The four initialisers leave
`baseline.json`.

### C16. `TabView` with plain-view content (SA-82)

*`TabView.init(content:)` and `TabView.init(selection:content:)` taking
plain views as pages, written `TabView { Text("A"); Text("B") }`, with or
without `.tag(_:)`*

The owner declined these on 2026-10-23 (SA-82-TABVIEW-PLAIN, option b).
`TabView(content:)` with `SelectionValue == Int` is not deprecated in SwiftUI,
and it takes plain views. On macOS, though, a page needs a label to appear in
the tab strip, and the only way to give a plain view one is `.tabItem`, which
is deprecated (in favour of `Tab`) and which TUI does not implement. TUI
would have had to invent the strip: numbered tabs, blank tabs as macOS shows,
or a page indicator. SwiftUI code that compiled would then show unlabelled
tabs.

`TabView` takes `TabContent` only (`Tab`, `TabSection`, `ForEach` and
conditionals of them), so plain-view content stays a compile error. That is
rule 2's correct failure, and it replaced the silent blank screen the semantic
audit found (item 82). The earlier 10-14 answer ("deprecated forms only") was
wrong about the SDK: the plain form is not deprecated. The decision rests on
the missing label source instead.

`parity-map.json` has no entry for it. It records absent symbols, and
`TabView.init(content:)` is present: the `Tab` form has the same name and
labels, so the tool's audit would call an entry for it stale. The compatibility
guide's `TabView` row carries the decline, and the Deliberate deviations page
no longer lists it, since a declined API belongs to rule 2 and not to that
page. Revisit if `.tabItem` is ever implemented.

### A50. Search in a tab view (macOS 26): the search tab and its activation

*`TabSearchActivation` (`.automatic`, `.searchTabSelection`),
`View.tabViewSearchActivation(_:)`; and `.searchable` written on a
`TabView`*

On macOS 26 `.searchable` on a `TabView` puts the search field into the tab
whose role is `.search`, and `.searchTabSelection` focuses the field when
that tab is chosen and goes back to the previous tab when the search is
dismissed. TUI draws `.searchable` on a tab view as it does on any view —
a field above the whole tab view — and has the `.search` role only as a
label. Nothing here could be measured: these are macOS 26 APIs, and this
machine runs 15.8.

**Options.**

1. **Implement as documented.** The tab view hands a `.searchable` written on
   it to its search tab's content (the field drawn at the top of that tab),
   and `.searchTabSelection` focuses it on selection (`SearchDismissal`
   already focuses a field) and reselects the previous tab on Escape. Half a
   day, and it should be measured on macOS 26 first.
2. **Defer** until a macOS 26 machine can measure it. Nothing compiles
   meanwhile, which is the honest state.

**Recommendation:** 2, then 1.

**Decided 2026-10-04: defer** until a macOS 26 or 27 pass can measure it.

*Lane 17d's entries (A53, B82–B83, C12), spring-loading and the drag-session family (refusal review P11, P18): measured on macOS 15.8 (SDK 26.2) by driving SwiftUI's spring-loading entry points; the session family is macOS 26's and is from its doc comments. Probes in `Tools/SwiftUIProbes/Spring loading (lane 17d)/`.*

### B-LISTS2-4. A sidebar's sections move among the identified sections, and a drag drops onto a header

*`TabViewCustomization`, `TabContent.customizationID(_:)` (decisions B79)*

**Shipped:** only a section with a customization identifier moves — the
order is stored by identifier — and it moves among the places identified
sections have, as a stated order is applied; the loose tabs between sections
keep theirs. A move writes the sections it orders into the places the stored
order gave them, so an identified section the sidebar does not show — its
tabs all hidden for now, or no header to move it by — keeps its stored
place. From the keyboard the section in hand is drawn faint and the
others step aside as it moves, and it goes back if the focus leaves its
header, as a list's row in hand does; a drag carries the header's title, and
a release over another header puts the section in that one's place.

**The fuller version:** a drag that shows a landing line between sections, as
a list's row reorder does, and drops above or below the header it is over by
which half of it the pointer is on. The sections are list rows, so the line
is the list's reorder slot drawn for a section's span of rows: about half a
day.

### B-LISTS2-8. A tab view sidebar is as wide as its widest tab, whatever its bottom bar

*`TabViewStyle.sidebarAdaptable` (found on the way to B76)*

The sidebar's column was a fixed-size stack of the header, the list, the
footer, the toolbar and the bottom bar. A list has no ideal width (SwiftUI's
has none), so the column took the widest of the others and drew the list at
it: a tab title wider than all of them was cut to them. **Shipped:** the
list is fixed on its own too, and answers its hugged width. Nothing to add.
