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

## C. Declined without asking

## D. Deferred to other waves or lanes
