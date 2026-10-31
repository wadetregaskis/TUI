# Compact size classes: popovers, split views and the tab popover

*What TUI does when an app writes a compact size class: a popover becomes a
sheet, a split view collapses to `preferredCompactColumn`, and a tab's popover
adapts too. Ids: A21, A21-TABPOPOVER; B3 is in
[Safe areas, size classes and layout direction](<../Layout and geometry/Safe areas, size classes and layout direction.md>).*

## In short

Size classes are the app's to set (B3). Under `.compact` a popover adapts to a
sheet (`presentationCompactAdaptation`), a `NavigationSplitView` collapses to
a stack showing `preferredCompactColumn`, and since 2026-10-24 a tab's popover
adapts as `View.popover`'s does (TUITabs now depends on TUIPresentation:
+3.1% for an app on TUIApp and TUITabs with no sheet of its own).

## The record

### A21. Compact-size-class adaptation and `preferredCompactColumn`

*`PresentationAdaptation` (`.automatic`, `.none`, `.popover`, `.sheet`,
`.fullScreenCover`), `View.presentationCompactAdaptation(_:)`,
`View.presentationCompactAdaptation(horizontal:vertical:)`,
`NavigationSplitView.init(preferredCompactColumn:…)` (all four)*

All of these say what to do in a compact size class: present a popover as a
sheet, show which split view column on top once the split collapses into one.
macOS is never compact, so on a Mac they are inert; TUI's size classes are
`.regular` unless an app sets them, and nothing TUI draws reads them (B3) —
the split never collapses and a popover never adapts.

**Options.**

1. **Leave them out** until B3 is decided.
2. **Ship them inert**, as macOS has them — under O8's option (b), citing
   the size classes never being compact here.
3. **Make them real:** a popover or sheet adapts by `PresentationAdaptation`
   when the environment's size class is compact (`.automatic` adapting a
   popover to a sheet, as iOS does), and a split view collapses into a stack
   showing `preferredCompactColumn` in a compact horizontal class. The
   adaptation is small (the popover presenter delegates to the sheet or cover
   presenter); the collapse is not (a split that becomes a stack keeps its
   columns' state and focus sections) — two days together. It only matters if
   B3 makes a narrow terminal compact.

**Recommendation:** decide with B3 and O8: 2 if O8 is (b) and B3 stays
"regular", 3 if B3 makes narrow terminals compact.

**Decided 2026-10-12, with B3: option 3, lane owed.** B3's ruling is that
TUI follows a compact class an app sets and changes no default, so when an
app writes `.compact` a popover must adapt and a split view must collapse;
shipping these inert would ignore the app's own setting. The defaults stay
regular, so nothing changes for an app that sets nothing. The work (about two
days, as priced above) goes with B3's lane.

**Shipped 2026-10-13: the popover half.** `PresentationAdaptation` and both
`presentationCompactAdaptation` modifiers ship, read from the popover's
content through the other presentation traits. In a compact class a popover
is a sheet (`.automatic`, `.sheet`), a full-screen cover (`.fullScreenCover`)
or stays a popover (`.none`, `.popover`). Where both classes are compact the
vertical class's adaptation wins, since a presentation is shortest of room
there; SwiftUI documents no order. The popover, sheet and cover presenters
are always all present around the presenting view, and the size class picks
whose binding is live, so a class written while the popover is up leaves the
presenting view's state alone. Not yet adapting: `TabContent.popover`, which
SwiftUI offers on iOS 18. TUITabs draws a tab's popover with Foundation's
`PopoverPresentationModifier` and does not depend on TUIPresentation, where
the sheet and the cover are; adapting it means that dependency, or an
environment hook the app installs. Left for a ruling: a tab's popover in a
compact class is an edge case, and the dependency is not free.

**Ruled 2026-10-23** (owner, A21-TABPOPOVER, option 1): TUITabs depends on
TUIPresentation, measuring first what that adds to an app that imports
only TUITabs. **Shipped 2026-10-24** (lane TABS): a tab's popover is shown
with `View.popover`'s adapting presenter (`_AdaptivePopover`, `package` for
it), so in a compact class it is a sheet, a cover or a popover still, as a
view's is; TUITabs re-exports TUIPresentation, and TUIPresentation
does not depend on it. **Its price,** measured 2026-10-24 (Xcode's Swift
6.2.4, release, default traits, `strip`): an app on `TUIApp` and
`TUITabs`, a tab with a popover, 8,731,120 → 8,997,600 B (+266,480 B,
+3.1%); the same app with a sheet of its own, which links TUIPresentation
already, 8,997,664 B before and after; an executable on `TUITabs` alone,
with no `App` (Tools/ProductSmoke's `UsesTUITabs`), 7,373,168 → 8,106,192
B (+733,024 B, +9.9%), TUIChrome coming with TUIPresentation there,
where `TUIApp` brings it to an app. The umbrella's apps pay nothing.

**Shipped 2026-10-13: the sheet's adaptation.** SwiftUI documents it: "In
vertically compact environments, such as iPhone in landscape orientation, a
sheet presentation automatically adapts to appear as a full-screen cover."
So in a vertically compact class a sheet is a cover (`.automatic`,
`.fullScreenCover`) or stays a sheet (`.none`, `.sheet`, and `.popover`,
there being no anchor for a sheet to become one at); in a horizontally
compact class alone it stays a sheet unless the content asks for a cover. A
sheet and a cover are one presenter whose style follows the class, so the
presented content keeps its state too, and `onDismiss` watches the app's
binding, so becoming a cover runs nothing. `modal(isPresented:)`, which
`sheet` forwards to, adapts with it.

**Shipped 2026-10-13: the split-view collapse.** In a compact horizontal
class a `NavigationSplitView` collapses into a stack: the column on top at
the full width, under a navigation stack's bar (the trail of the columns'
titles, or ‹ Back) when it is not the sidebar, with Escape and `\.dismiss`
going back a column. The four `preferredCompactColumn:` initializers ship;
without one the split keeps the column itself, starting at the sidebar, as
SwiftUI's documentation describes a collapsed split starting with its first
list. Choosing a row of a `List` with a selection — Return, Space or a
click — selects it and shows the next column, as tapping one does on
iPhone; the row stays selected, so coming back and choosing it again goes
forward again rather than clearing it. Column visibility, the handles, the
widths and the sidebar chords are set aside while collapsed, as SwiftUI
ignores visibility there. The columns behind the one on top render
off-screen, as a stack's root does, and keep their state; a column ahead of
it is not drawn. A `Table` chooses its rows the same way since the compact
`Table` (B3). A `NavigationLink` in the column on top pushes its destination
onto the collapsed stack, over that column (lane TOOLBARS, 2026-10-19); in a
regular class a split's links still push only within a `NavigationStack`
(decisions TOOLBARS, B-TOOLBARS-3).
