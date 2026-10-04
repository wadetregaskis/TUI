# Completing the SwiftUI API: Wave 8b decisions (tabs, list editing and styling)

*Wave 8b's entries for
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md),
in its format, to be folded in and renumbered there. SwiftUI's behaviour was
measured on macOS 15.8 (built against the macOS 26.2 SDK) with an offscreen
`NSHostingView`; the probe sources are in the session notes (`w08b/probe/`),
not in the repository. macOS 26 APIs could not be probed.*

---

## A. Needs your decision

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

## C. Declined without asking

## D. Deferred to other waves or lanes
