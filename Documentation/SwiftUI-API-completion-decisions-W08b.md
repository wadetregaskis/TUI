# Completing the SwiftUI API: Wave 8b decisions (tabs, list editing and styling)

*Wave 8b's entries for
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md),
in its format, to be folded in and renumbered there. SwiftUI's behaviour was
measured on macOS 15.8 (built against the macOS 26.2 SDK) with an offscreen
`NSHostingView`; the probe sources are in the session notes (`w08b/probe/`),
not in the repository. macOS 26 APIs could not be probed.*

---

## A. Needs your decision

### A-W08b-1. Should a list look like SwiftUI's by default — borderless?

*`DefaultListStyle`, `ListStyle.automatic`*

The table's question (A29) asked of lists. Measured on macOS 15.8: a SwiftUI
`List` with no style, and one with `.inset`, is an `NSTableView` of style
`.inset` in a scroll view with no border; `.bordered` is style `.fullWidth` in
a line-bordered scroll view; `.sidebar` is `.sourceList`; `.plain` is `.plain`.
None stripes its rows.

Shipped: `.automatic` is the bordered box every TUIkit list has always drawn,
and `.bordered`, `.inset`, `.plain` and `.sidebar` draw as named.

**Options.**

1. **Bordered by default** (shipped). The divergence is the default alone.
   Free.
2. **SwiftUI's default: `.inset`.** Every list without a style loses its
   border, which gives its rows two lines and moves every click target a line
   up and a cell left, and its title (drawn in the top border today) needs a
   line of its own. Golden and render tests that read a list's bytes need
   re-baselining. Half a day, most of it the tests.

**Recommendation:** answer it with A29, the same way. A list and a table side
by side should not disagree about whether they are boxed; whichever answer
A29 gets, this one takes.

### A-W08b-2. List separators: draw them, or decline them?

*`View.listRowSeparatorTint(_:edges:)`, `View.listSectionSeparator(_:edges:)`,
`View.listSectionSeparatorTint(_:edges:)`,
`HorizontalAlignment.listRowSeparatorLeading`,
`HorizontalAlignment.listRowSeparatorTrailing`; and the existing
`listRowSeparator(_:edges:)`, inert since it shipped*

Measured on macOS 15.8 (`w08b/probe/sections-*.png`): an `.automatic`,
`.inset`, `.bordered` and `.plain` list draws a hairline under every row,
inset to the row's content, and under every section header; `.sidebar`
draws none. A hairline is thinner than a cell. TUIkit draws no separators,
and `.listRowSeparator(_:)` is accepted and does nothing — a silent no-op
of the kind this effort otherwise refuses.

**Options.**

1. **Underline the row's last line.** The separator becomes an underline
   (SGR 4) across the row's cells from the separator's leading alignment to
   its trailing one: no line of height spent, `.hidden` drops it, a tint is
   the underline colour (SGR 58, whose support per terminal is not yet
   recorded in `Terminal-compatibility.md`; where it is ignored the line
   takes the text's colour). A selected or focused row's underline sits
   inside its highlight. A day: the list's row composition, the alignment
   guides, the tints, and measuring SGR 58 with the terminal probes.
2. **A rule line between rows.** A `─` line in the faint ink: doubles every
   list's height, which no terminal list wants. Half a day; not recommended.
3. **Decline the family by reason** (a terminal row has no sub-cell rule, and
   a line of height per row is too dear), and turn `listRowSeparator` into a
   declined API too, removing it — pre-1.0, no compatibility shim. An hour.

**Recommendation:** 1 if separators are wanted at all — it is the only
answer that keeps a list's height; else 3, which at least stops
`listRowSeparator` pretending.

### A-W08b-3. Swipe actions: which keys and which pointer gesture?

*`View.swipeActions(edge:allowsFullSwipe:content:)`,
`TabContent.swipeActions(edge:allowsFullSwipe:content:)`*

A macOS list row reveals its swipe actions on a two-finger trackpad swipe
toward the edge they belong to; a full swipe performs the first. A terminal
has no swipe, and an action only the pointer reaches breaks the
no-mouse-only rule, so the route has to be chosen.

**Options.**

1. **A menu, from a chord and a horizontal scroll.** On the focused row, a
   row shortcut (bindable through `.rowShortcuts`, say Ctrl-L for the
   leading edge and Ctrl-T for the trailing) opens the edge's actions as the
   context-menu engine's menu, anchored at that edge of the row; a
   horizontal wheel event over a row (what a trackpad swipe sends in a
   terminal that reports the wheel) opens the same menu, and a full swipe is
   not modelled. Half a day: the menu, the shortcuts and the wheel are all
   there.
2. **Revealed buttons in the row.** The chord or the horizontal wheel slides
   the actions in at the row's edge, over its trailing cells, as macOS draws
   them; Tab moves through them and Escape slides them away; a second
   horizontal wheel in the same direction is the full swipe. Closer to
   macOS, and a day and a half: the row needs a revealed state the list draws
   and memoises, and its focus ring has to admit the buttons.
3. **Decline** by reason: a gesture the terminal does not have.

**Recommendation:** 1. A swipe action is a context menu for one edge, and the
menu brings its keyboard handling, dismissal and colours with it.

### A-W08b-4. Per-tab interactions: context menus, popovers, drag and drop

*`TabContent.contextMenu(menuItems:)`,
`TabContent.popover(isPresented:attachmentAnchor:arrowEdge:content:)`,
`TabContent.popover(item:attachmentAnchor:arrowEdge:content:)`,
`TabContent.draggable(_:)`, `TabContent.dropDestination(for:action:)`,
`TabContent.springLoadingBehavior(_:)`*

These surfaced once `TabContent` existed. In a `.sidebarAdaptable` sidebar a
tab is a list row, and each would be the view modifier of the same name on
that row — free. In a strip, a tab is a chip the tab view's core draws and
hit-tests by column, so each needs the chip to carry its own regions: a
right-click and Shift+F10 on the focused chip for the menu, an anchor for
the popover, a press-and-move for the drag, a hover target for the drop
(and spring loading: a drag held over a chip selects that tab, as macOS
does). `SpringLoadingBehavior` itself is not in TUIkit yet.

**Options.**

1. **All six, in both looks.** A day and a half, most of it the strip's
   per-chip regions, which all six share.
2. **The sidebar only**, with each refused in a strip — not possible as a
   compile-time refusal (the style is chosen at run time), so the strip would
   ignore them: a silent no-op. Not recommended.
3. **Decline** by reason: a terminal tab strip is a row of labels, not of
   controls.

**Recommendation:** 1, after the table rows' drag and drop, which builds the
"a drawn row carries its own drag regions" half of it.

### A-W08b-5. Search in a tab view (macOS 26): the search tab and its activation

*`TabSearchActivation` (`.automatic`, `.searchTabSelection`),
`View.tabViewSearchActivation(_:)`; and `.searchable` written on a
`TabView`*

On macOS 26 `.searchable` on a `TabView` puts the search field into the tab
whose role is `.search`, and `.searchTabSelection` focuses the field when
that tab is chosen and goes back to the previous tab when the search is
dismissed. TUIkit draws `.searchable` on a tab view as it does on any view —
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

### A-W08b-6. `sectionIndexLabel(_:)` joins O8

*`View.sectionIndexLabel(_:)` (both)*

A macOS 26 modifier naming a section in a list's section index — the
A-to-Z strip down an iOS list's edge. macOS has no section index:
`listSectionIndexVisibility(_:)` is not in the macOS SDK, so on macOS the
label is inert. Exactly O8's question (APIs inert on macOS too); it ships or
is declined with O8's answer. Shipping it inert is ten minutes.

## B. Shipped the safe option

### B-W08b-1. Badge prominence: two inks, read from the list's environment

*`BadgeProminence` (all members), `EnvironmentValues.badgeProminence`,
`View.badgeProminence(_:)`*

Measured on macOS 15.8, in a `List` of the default style and of the sidebar
style alike: a `.standard` badge is bold grey text in a light grey capsule; a
`.decreased` one is lighter grey text with no capsule; an `.increased` one is
drawn exactly as a `.standard` one (the same pixels).

TUIkit's list badge has always been plain text in the palette's tertiary
foreground, which is closer to macOS's `.decreased` than to its `.standard`.

**Shipped:** `.standard` keeps that look, `.decreased` draws in the quaternary
foreground (the dimmest text a palette has), and `.increased` draws as
`.standard`, as measured. The list reads the prominence from its own
environment, so `.badgeProminence(_:)` works on the list or anything around it.
Written inside a row — around or within the row's `.badge(_:)` — it does not
reach that badge: the list draws a row's badge itself, from the row's view
value, in the list's environment.

**The fuller version** has two parts.

- **A capsule for `.standard`.** Draw the badge on a tinted field one cell
  wider on each side (` 12 `), the terminal's capsule, and keep today's plain
  text for `.decreased`. This changes every badged list's look, and every
  golden or render test that reads a badged row needs re-baselining. Half a
  day, most of it the tests and choosing the field colour per palette (it has
  to read on the cursor row's breath too).
- **A row's own prominence.** Read a `.badgeProminence(_:)` written inside the
  row by peeling the environment modifier off the row value the way the badge
  is peeled off, or by rendering the row's badge inside the row's own
  environment. A couple of hours; nothing else changes.

### B-W08b-2. Background prominence: raised on the rows a list builds itself

*`BackgroundProminence` (all members), `EnvironmentValues.backgroundProminence`*

SwiftUI raises the prominence for the content of a focused list's selected
rows, whose fill is the vivid accent, and resolves the system content styles
there to a monochrome that keeps their contrast.

**Shipped:** a `List` and a `Table` raise it for the row under the cursor while
the control has the focus, when that row is also selected (in a table, for its
view cells) — the row whose fill is the accent's
breath (TUIkit has one cursor, so one row; SwiftUI raises every selected row of
a focused list, all of which it fills alike). The content levels `.primary`
through `.quinary` resolve to the palette's own text tiers under a raised
background, whatever foreground style the row inherited: those are the inks the
row fills were chosen to carry. The list clears the raised row's cached renders
on the frame the raise moves, since the value reaches the row through its
environment and no memo below the row would notice it.

Raised: every row the list builds lazily — the rows of a `ForEach` and an
`OutlineGroup`, which is every data-driven list. **Not raised:** a hand-written
row beside them (`List { Text("All"); ForEach(items) { … } }`), which the
list's child walk hands over already drawn, before anyone knows where the
cursor will be.

**The fuller version:**

- **Hand-written rows.** Draw them lazily too — keep the child's render
  closure in the row's content box, as a looped row's is — and the raise
  reaches them unchanged. Half a day, most of it the child walk's badge and
  tag reads, which today come off the drawn row.
- **`.background(.selection)`.** SwiftUI says its selection style raises the
  content above it too. A `background(_:)` whose style is `.selection` would
  set the value for its content. An hour.

### B-W08b-3. `\.sidebarRowSize` is read-only (always `.medium`)

*`SidebarRowSize` (all members), `EnvironmentValues.sidebarRowSize`*

On macOS the value follows the "Sidebar icon size" setting, and a write
forces a sidebar's rows — their height and their `Label` icons — to that
size. Off macOS SwiftUI always reports `.medium` and ignores a write.

A terminal row is one line in the terminal's one font, so TUIkit's is always
`.medium`. **Shipped:** the type with its three cases, and the value
read-only, so a write fails to compile rather than being ignored (the B1/B2
precedent).

**The fuller version** would make the value settable with a meaning a
terminal can give it — `.large` adding a blank line under each sidebar row,
say, and `.small` dropping a `Label`'s icon. Neither is what the setting means
on macOS, so it is not recommended without a use for it.

### B-W08b-4. A tab's label is drawn as text

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

### B-W08b-5. The sidebar style: a list beside the content, chosen with Return

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
  Space or a click choose the tab — TUIkit's list convention. A macOS sidebar
  selects as the cursor moves. Following the cursor needs a list mode that
  selects as it moves (a `List` option of TUIkit's own, or the sidebar style
  watching the cursor), about two hours; whether every keystroke should swap
  the content beside it is the question.
- **The header and footer stay put.** SwiftUI's header and footer scroll with
  the tabs; here they are fixed above and below the list, and only the tabs
  scroll. Moving them into the list as a first and last row is an hour, but a
  header that is a row is a row the cursor must step over.
- **Sections are not collapsible.** macOS lets the user fold a sidebar
  section. That comes with `Section(isExpanded:)` in a list, which the sidebar
  would then use.

### B-W08b-6. Type select moves the cursor, and a prefix's first character gives way to bare-key bindings

*`View.typeSelectEquivalent(_:)` (all four)*

macOS type select, in a focused table or outline: typing a few characters
selects the first row after the selection whose text starts with them, and a
key no row answers to beeps.

**Shipped:** with a list or table focused, a typed character without Control
or Option (and not Space, which selects) joins a prefix, which a second's
pause starts afresh; the next render moves the cursor to the first row whose
text starts with the prefix, ignoring case — after the cursor for a first
character, at it for a longer prefix — and scrolls it into view. A row's text
is its stated `typeSelectEquivalent(_:)`, else a list row's first line of text
(drawn as a measure for a row out of sight, which registers nothing) or a
table row's first column. An empty equivalent takes the row out.

Where it differs:

- **The cursor moves, not the selection.** TUIkit's lists and tables move the
  cursor with the arrow keys and select with Return or Space; type select
  follows them. Selecting as well is a line, if the owner prefers macOS's
  behaviour for this one gesture.
- **A prefix's first character gives way to bare-key bindings.** macOS's
  shortcuts take Command, so its type select never meets one; TUIkit binds
  bare keys — its own `q` (quit), `t` (theme), `a` (appearance) and help key,
  and any bare `.keyboardShortcut` an app registers. The first character of a
  prefix goes to such a binding (the Stress `themes` session presses `t` with
  a list focused, and caught it); once a prefix is under way every character
  continues it, or typing "Atlas" would cycle the theme at the `t`. So a row
  whose name starts with a bound letter is not found by typing that letter
  first. Any other character is taken whether or not a row answers to it, as
  macOS takes it. The alternative — resolve the prefix when the key arrives
  and pass on a key no row answers to — needs every row's text at key time,
  measured outside a render; a day.
- **A looped row spliced among hand-written rows** (a `ForEach` beside a
  static row) is matched by its drawn text; an equivalent it states is not
  seen, behind the memo the list wraps such rows in. Half an hour with the
  badge's own unwrapping (`extractRowBadgeValue`).

### B-W08b-7. Section actions: always shown, after the header's title

*`View.sectionActions(content:)`, `TabContent.sectionActions(content:)`*

macOS shows a list section's actions at the trailing end of its header while
the pointer is over the section.

**Shipped:** in a `List`, the actions are drawn one cell after the header's
title, all the time, and are ordinary controls there — Tab moves onto each, a
click presses one. A section with no header shows them alone on the header's
line. A custom container reads them as `SectionConfiguration.actions`.
Outside a list (a `Section` in a stack) the view draws as it would without
them, as SwiftUI's does. On a `TabSection`, a `.sidebarAdaptable` tab view's
sidebar draws them the same way; a tab strip, which lists a section's tabs
among the others, shows none, and on a lone `Tab` they do nothing, as
SwiftUI documents.

Where it differs:

- **Always shown.** An action shown only under the pointer is one the
  keyboard cannot reach; showing them while the focus is inside the section
  as well as on hover is a line, if the owner prefers the quieter header.
- **After the title, not flush right.** The list builds a header row before
  it knows the width a hugging list (a sidebar) settles on, so a flush-right
  action there would lose its trailing cells. Flushing right in a list that
  fills its width, and after the title in one that hugs, is half a day: the
  header row would carry the actions apart from its buffer and the list
  would place them as it places a badge.
- **An environment modifier between the section and `.sectionActions`**
  (`Section { … }.headerProminence(.increased).sectionActions { … }`) hides
  the section from the list, which draws it without its actions — checked in
  a test run. That is the list's own limit: it does not see a `Section`
  through an environment modifier, with or without actions.

### B-W08b-8. Tab view customization is the app's to change; no gesture changes it

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

**Shipped:** all of it, as measured, with the B45 shape: a hidden tab leaves
the sidebar and not a strip; a stated tab order (per section) and section
order are applied to the sidebar, the identified items taking the slots
identified items had; `Codable` in TUIkit's own encoding; persisted through
`@AppStorage`/`@SceneStorage` with no default written. The binding is read,
never written: the environment carries the value, not the binding, so the
render memos below the tab view stay on.

Where it differs:

- **No gesture reorders sections.** macOS drags them; a keyboard pair to move
  the focused section up and down needs a notion of a focused section the
  sidebar list does not have — about a day, with a decision on whether the
  list's cursor row or its section header is the thing moved. So a stated
  order comes only from the app or a decoded value.
- **`.defaultVisibility(_:for:)` and `.customizationBehavior(_:for:)` do
  nothing**, as on macOS: the placement the first acts on (`.sidebar`) and the
  behaviors the second restricts (`.reorderable`, `.disabled`) are not
  macOS's, so no macOS source can ask either for anything.

### B-W08b-9. Table row drag and drop: the row's own line, a selected look, flat loops

*`TableRowContent.draggable(_:)`, `TableRowContent.dropDestination(for:action:)`,
`TableRowContent.itemProvider(_:)`, `ItemProviderTableRowModifier`,
`DynamicTableRowContent.dropDestination(for:action:)`,
`DynamicTableRowContent.onInsert(of:perform:)`, `OnInsertTableRowModifier`*

Wave 8a's deferral (priced at a day and a half), built on the drag session
`List` rows and `.draggable` views already use.

**Shipped:** a press on a row that carries a payload, then any movement,
starts a drag with the row's own line under the pointer (morphing from the
grid's layout to a carried row's, as a `.cursor` reorder's does); a release
over anything that takes the payload — a view's `.dropDestination`, another
row's, a table or list that inserts it — delivers it, and a press released
without moving is a click on the row. A row's own `.dropDestination(for:action:)`
takes drops onto itself. A loop's `.dropDestination(for:action:)` and
`.onInsert(of:perform:)` take payloads between its rows, the table opening the
gap `Table.dropDestination` already opens, and report the offset into the
loop's own collection, counting from its first row whatever rows come before
it, as SwiftUI's `onInsert` offsets are. Item providers are Apple-only, as
the view forms are.

Where it differs:

- **The targeted row is drawn as a selected row.** macOS rings the row a drop
  would land on in the accent; a ring needs a cell around the row, which the
  grid does not have. The selection fill is the nearest drawn answer, and
  goes when the drag leaves.
- **A draggable row is not picked up by `Table.onMove(_:)`** (TUIkit's own
  table-level reorder): the press carries the payload. SwiftUI's tables have
  no `onMove`; their reorder is a loop's `dropDestination` with draggable
  rows, which works here too.
- **A hierarchical table's loops take no insertions**: there the drawn rows
  are the open tree's, not one loop's, and an offset into a loop under a
  closed branch has no drawn slot. An hour or two, if wanted, to map the slot
  to the loop whose rows it falls among by walking the outline.

## C. Declined without asking

## D. Deferred to other waves or lanes
