# Badges and the prominence of a row

*How a list row's badge is drawn, and how a selection or a background raises
the prominence of what sits in front of it. Ids: B72, B72-CAPSULE, B73, B74,
B-LISTS-1, B-LISTS2-1.*

## In short

A `.standard` badge sits on a field of the control face's tint (a capsule
between the cap set's caps under Lines); `.decreased` draws plain in a quieter
ink. A list or table raises the background prominence of the row under the
cursor and of selected rows, and a `.background` raises it for what is drawn in
front of it, so text on a highlighted row keeps its contrast.
`\.sidebarRowSize` is read-only (`.medium`).

## How it unfolded

1. **B72 and B73** shipped the two inks and the raised prominence on the rows a
   list builds itself; B74 left the row size read-only.
2. **2026-10-18 to 19, lanes LISTS and LISTS2** read a row's badge through
   environment writes only (B-LISTS-1) and made a background raise prominence
   in both its spellings (B-LISTS2-1).
3. **2026-10-23 to 24, B72-CAPSULE.** The owner asked for mock-ups of options B
   and C, then chose (c): the capsule, built by lane CAPS.

## For a future reader

- **A row the app wrote by hand that loses contrast** only because it was
  hand-written was treated as a correctness defect (the B73 ruling); keep it
  so.

## The record

### B72. Badge prominence: two inks, read from the list's environment

*`BadgeProminence` (all members), `EnvironmentValues.badgeProminence`,
`View.badgeProminence(_:)`*

Measured on macOS 15.8, in a `List` of the default style and of the sidebar
style alike: a `.standard` badge is bold grey text in a light grey capsule; a
`.decreased` one is lighter grey text with no capsule; an `.increased` one is
drawn exactly as a `.standard` one (the same pixels).

TUI's list badge has always been plain text in the palette's tertiary
foreground, which is closer to macOS's `.decreased` than to its `.standard`.

**Shipped:** `.standard` keeps that look, `.decreased` draws in the quaternary
foreground (the dimmest text a palette has), and `.increased` draws as
`.standard`, as measured. The list reads the prominence from the environment
each badge is written in: its own, so `.badgeProminence(_:)` works on the list
or anything around it, or one written on a row around its `.badge(_:)`, which
wins over the list's. Written inside the badge (`.badgeProminence(.decreased)
.badge(5)`) it does not reach it. Both measured on macOS 15.8
(`Tools/SwiftUIProbes/Badge prominence/badgeprom.swift`); since 2026-10-18
(lane LISTS). A badge with another kind of modifier after it is a gap of its
own (B-LISTS-1).

**And the capsule (owner, B72-CAPSULE (c), 2026-10-23; shipped
2026-10-24):** a `.standard` or `.increased` badge sits in a capsule in the
control family (`ListBadgeCapsule`): under filled faces, the default, a field
a cell wider each side, ` 12 `, in the control face's resting tint (a
button's at rest, `restingControlFace`, spent over the list's surface; blank
where the accent's tint cannot be measured), its text the badge's ink floored
against it; under `.controlStyle(.lines)` the cap set's caps on no field,
`(12)`, `│12│` in a rounded rectangle, from the table a button reads
(`ControlEnds`); none under `.blank`. A `.decreased` badge stays plain text,
as macOS draws it. The capsule's cells are the badge's in the list's hug, its
badged line's fit and its claims alike. The field is the same on every row:
on the cursor's and a selection's fill it reads as a darker capsule on the
lighter row.

### B73. Background prominence: raised on the rows a list builds itself

*`BackgroundProminence` (all members), `EnvironmentValues.backgroundProminence`*

SwiftUI raises the prominence for the content of a focused list's selected
rows, whose fill is the vivid accent, and resolves the system content styles
there to a monochrome that keeps their contrast.

**Shipped:** a `List` and a `Table` raise it for the row under the cursor while
the control has the focus, when that row is also selected (in a table, for its
view cells) — the row whose fill is the accent's
breath (TUI has one cursor, so one row; SwiftUI raises every selected row of
a focused list, all of which it fills alike). The content levels `.primary`
through `.quinary` resolve to the palette's own text tiers under a raised
background, whatever foreground style the row inherited: those are the inks the
row fills were chosen to carry. The list clears the raised row's cached renders
on the frame the raise moves, since the value reaches the row through its
environment and no memo below the row would notice it.

Raised: every row the list builds lazily — the rows of a `ForEach` and an
`OutlineGroup`, which is every data-driven list — and, since 2026-10-19 (lane
LISTS2), a hand-written row beside them (`List { Text("All"); ForEach(items)
{ … } }`), in a section or alone, which the list's and the section's child
walks used to hand over already drawn, before anyone knew where the cursor
would be. They are drawn when the list reads them now, as a looped row is.

**The fuller version:**

- **Hand-written rows.** Draw them lazily too — keep the child's render
  closure in the row's content box, as a looped row's is — and the raise
  reaches them unchanged. **Shipped (2026-10-19, lane LISTS2).**
- **`.background(.selection)`.** SwiftUI says its selection style raises the
  content above it too. **Shipped (2026-10-19, lane LISTS2):** a
  `background(_:)` or `background(_:in:fillStyle:)` whose style is
  `.selection`, erased in an `AnyShapeStyle` or not, sets the value for its
  content, noted with the render cache so a memo below follows an erased style
  that changes; no other style raises it.

### B74. `\.sidebarRowSize` is read-only (always `.medium`)

*`SidebarRowSize` (all members), `EnvironmentValues.sidebarRowSize`*

On macOS the value follows the "Sidebar icon size" setting, and a write
forces a sidebar's rows — their height and their `Label` icons — to that
size. Off macOS SwiftUI always reports `.medium` and ignores a write.

A terminal row is one line in the terminal's one font, so TUI's is always
`.medium`. **Shipped:** the type with its three cases, and the value
read-only, so a write fails to compile rather than being ignored (the B1/B2
precedent).

**The fuller version** would make the value settable with a meaning a
terminal can give it — `.large` adding a blank line under each sidebar row,
say, and `.small` dropping a `Label`'s icon. Neither is what the setting means
on macOS, so it is not recommended without a use for it.

### B-LISTS-1. A row's badge is read through environment writes only

*`View.badge(_:)`, `View.badgeProminence(_:)` on a `List` row (decisions B72)*

Measured on macOS 15.8 (`Tools/SwiftUIProbes/Badge prominence/badgeprom.swift`):
a `.badgeProminence(_:)` written on a row around its `.badge(_:)` is that
badge's, and wins over the list's; one written inside the badge is not; and a
badge with a padding after it, `.badge(5).padding(.leading, 0)`, is still
drawn, with a prominence written around the padding reaching it.

**Shipped:** a `List` reads a row's badge, and the prominence written around
it, through any number of environment writes after the `.badge(_:)`
(`.badge(5).badgeProminence(.decreased)`, `.badge(5).environment(…)`). It is
a conditional conformance of `EnvironmentModifier` to the badge carrier, so
the windowed list's type gate (`viewTypeCarriesBadge`) still answers from
the row's type alone, and a row without a badge pays nothing for it.

**Not shipped:** a badge with any other modifier after it — a padding, a
frame, a foreground style — is still not seen as the row's badge, and the row
draws without one, where SwiftUI draws it. Before this lane that was also true
of an environment write after the badge.

**The fuller version:** read the badge through every single-content wrapper,
as the container-value walk (`throughWrappers`) does for a tag or a z-index.
The badge gate is asked of every row on every frame, and it is a single cached
conformance check today; walking the row's type through its wrappers is a
cast per wrapper per row per frame, on the windowed path of every list. About
two hours, plus an A/B on `megalist`, `session` and `inbox`.

### B-LISTS2-1. A selection background raises the prominence of what is in front of it, in its two spellings

*`ShapeStyle.selection` (`SelectionShapeStyle`), `EnvironmentValues.backgroundProminence`,
`View.background(_:)`, `View.background(_:in:fillStyle:)` (decisions B73)*

SwiftUI documents that "standard shape styles like `ShapeStyle.selection`
will automatically update the background prominence of foreground views".
Its own behaviour could not be measured: a probe (`LISTS2/probe/selprom.swift`
in the working notes) could not make its offscreen window key, and in a
window that is not key neither a selected list row nor a `.selection`
background raised.

**Shipped:** `background(_:)` and `background(_:in:fillStyle:)` raise it for
their content when the style is `.selection`, erased in an `AnyShapeStyle` or
not; no other style does. TUI's selection style is drawn vivid always, as a
terminal's one window is always the key one, so it raises always.

**Not shipped:** the selection drawn by a view rather than a style —
`.background { Rectangle().fill(.selection) }`, `ZStack { Color… }` — and a
modified selection (`.selection.opacity(0.5)`, `.selection.shadow(…)`). The
first would need the view background to look through its content for the
fill it draws; the second, each style wrapper to forward the answer. About
an hour for the wrappers, and the view form is not recommended without a
measurement saying SwiftUI raises it.
