# Tooltips — `help(_:)` in a terminal

**Status: shipped, 2026-09-09; extended 2026-10-12 to views that cannot take
the focus.** The owner ruled on 2026-10-12 that `help(_:)` must work on them,
by hover and by an app-wide help feature. Hover always did. The app-wide
feature is `.tooltips(.always)`, whose panels now avoid one another (§5, "Many
panels at once"); a keyboard route of its own for such a view is not built
(decisions [HELP](<../SwiftUI parity/Decisions/Presentation and windows/Help on views that cannot take the focus (HELP).md>) B-HELP-2), nor is the
owner's punted "help browse" mode. Two defects found then are fixed: a focus-revealed
tooltip never reached the status bar, the default presentation, so `?` showed
nothing with the default style; and `.onFocus` with a delay above zero never
showed, because its delay restarted every frame. Both came from clearing the
focus candidate at the top of every walk: the bar is sized before the walk
republishes it, and a frame runs that reset twice. The candidate now lives
until the end of a frame whose drawn walk did not publish it again, or until
the focus moves off its control (`TooltipState.beginWalk`, `endFrame`,
`syncFocus`); `HelpRunLoopTests` drives both through the run loop. And as
the bar is sized before the walk, a walk that changes what it shows (a Tab
under `.onFocus` with no delay, revealed help whose text changes, help the
focused control drops) asks for the next frame, which draws it; and a
view with help that the frame's reshape slides under a resting pointer gets
the wake at the end of its delay, which it could not ask for itself, having
drawn already (`RenderLoop.requestTooltipFrames`; a review found both gaps).
`help(_:)`, `TooltipState`, `TooltipStyle`,
`TooltipTrigger` (`.never` / `.automatic` / `.onFocus` / `.always`), the three
subtree modifiers, the `?` help key and **both presentations** are on `main`. What is not built is §5's rules 4 and 5 — prefer a
placement not under the pointer, and re-wrap to a narrower box before rejecting a
placement. Both are new constraints on
`OverlayLayer.placed(maxWidth:maxHeight:)` rather than uses of it, and the design
itself ranks rule 4 below 1–3; the panel takes the placement the shared rule
gives it. The panels of `.always` avoid one another since 2026-10-12: they
are placed as a set (§5, "Many panels at once"). §7's three open questions are answered by the code: the tooltip row
sits ABOVE the shortcut items so both show (Q1), innermost wins by ordinary
environment cascade (Q2), and `help(_:)` does make a `Text` hit-testable, which
its own doc comment now says (Q3). Written before building because
the affordance is the expensive part to change later, and because mapping the
spec onto the render loop turned up two things the spec could not have known.

**Two decisions taken during implementation, both departures from §1 and §8.**

1. **The presentation choice was confirmed as the owner's own** — both
   presentations, app-selectable — and the owner asked for the popover as well as
   the bar rather than the bar first. §4 and §5 both stand; §8's staging order is
   the only thing that changed.
2. **A focus candidate is revealed by the help key, not automatically** — and
   that **deletes §3 entirely**. §3 wants `focus(id:reason:)` because a tooltip
   that auto-shows on focus has to tell a Tab from a click, or it pops up under
   every click. A key press is unambiguously the keyboard asking, so the question
   never arises, and a shared API that turned out to have 33 call sites (not the
   five §3 counted) did not have to change. §3 is kept below as the record of a
   problem that dissolved rather than one that was solved.

**The key is `?`, and it has one known hole.** `?` is punctuation, and
`InputHandler`'s layer 0 gives a focused text control first refusal on every
printable key — so inside a `TextField`, `SecureField`, `TextEditor` or
`DatePicker`, `?` is typed and the help key is never reached. That precedence is
right (a help key must not stop the reader typing a question mark) and the gap is
real: the controls whose help most needs explaining are the ones the key cannot
reach. Hover still works there, and `TooltipState.helpKey` is settable. An F-key
would not have the problem and was declined by the owner for a worse one — F-keys
are frequently claimed system-wide, so they fail elsewhere and less visibly.
`HelpKeyTests.textFieldSwallowsTheHelpKey` pins the behaviour, so a change to
that precedence fails a test rather than surprising someone.

The specification is the project owner's, and is taken as given:

- SwiftUI's `help(_:)`, shown on **mouse hover after a configurable delay** or
  on **keyboard focus** — but *not* when focus arrives from a mouse click.
- A view that cannot take focus shows its tooltip on hover only.
  (Superseded 2026-10-12: also through an app-wide help feature,
  `.tooltips(.always)`; see the status above.)
- Tooltips are switchable on and off, and the **presentation is the app's
  choice**, from (1) a row in the status bar above the shortcuts, or (2) a
  popover attached to the control.
- Presentation (1) first, then evaluate whether the varying height disturbs
  the content.

---

## 1. Where the help text lives

`help(_:)` goes on *any* view, so it cannot ride the focus system — most views
it will be written on are not focusable. What every such view needs is a
hit-test region, so the pointer can be known to be over it, and TUIkit already
has the modifier that establishes one: `.onHover`.

So `HelpModifier` is `.onHover` plus a publication, and it publishes to a
per-frame sink in the environment — the same shape as
`StatusBarState.activationLabelOverride`, which is already how a focused
control contributes a string to the bar.

```
HelpModifier(content, text)
  ├─ .onHover { entered in tooltips.hovering(text, at: <region>, entered) }
  └─ if context.environment.isFocused { tooltips.focusing(text, at: <region>) }
```

`TooltipState` (a service, not a singleton — one per `TUIContext`, as
`StatusBarState` is) holds at most one candidate: its text, its anchor
rectangle, its source (hover or focus), and the moment it became a candidate.

**Hover wins over focus** when both are true. The pointer is a deliberate act
aimed at one thing; focus is where the keyboard happens to be.

## 2. The delay, and what it costs

A hover tooltip appears only after the pointer has rested. That needs a clock,
and the run loop is demand-driven — it renders when something asks. So
`TooltipState` must **request a wake** at the moment the delay expires, exactly
as an animation asks for its frames (here the one-shot `context.requestWake`), or
the tooltip appears only
if something else happens to redraw.

That is one scheduled wake per hover, not a poll, and it stops as soon as the
tooltip is shown or the pointer leaves. A tooltip that is already showing costs
nothing.

## 3. "Not when focus arrives from a click" — answered by the delay, not by a reason

**Resolved 2026-09-09.** This section argued that auto-showing on focus needs
`FocusManager.focus(id:reason:)` — `.keyboard` / `.pointer` / `.programmatic` —
because five call sites drive focus from a mouse handler (`FocusableModifier`,
`TextFieldMouseHandler`, `Color256Grid`, `_PickerMenuCore`, and
`FocusReference`), and a tooltip that cannot tell those from a Tab pops up on
every click.

The argument was sound against the design it was written for: auto-show as the
*default* behaviour of `help(_:)`, revealed immediately. Two things changed and
the requirement went with them.

**The reveal became opt-in.** `TooltipTrigger.automatic` reveals a focus
candidate only on the help key, and `.onFocus` is a mode an app asks for. In
that mode, a clicked control explaining itself is the promise being kept, not a
defect.

**The delay applies to the focus slot too.** So a click resolves like this:
the pointer is by definition over the control it clicked, so `.entered` has
already published a *hover* candidate — with the same delay — and hover wins.
The tooltip that appears after a click is the one that would have appeared
without it. `focus(id:reason:)` would buy exactly one case: click, move the
pointer off within the delay, and rest on nothing. There, `.onFocus` shows the
clicked control's help, which is what `.onFocus` says it does.

So the shared API did not have to change. The residue worth naming is that a
terminal with no motion reporting has no hover at all, and there `.onFocus` is
the only route a tooltip has — which makes it a feature rather than a leak.

## 4. Presentation 1 — a status-bar row

`StatusBar.height` is `style.barHeight(contentRows: 1)`; the tooltip makes that
`1 + wrapped lines`. The content area is whatever is left.

**No second pass is needed, and my first reading of this was wrong.** It said
the height would be known a frame late because the tooltip's text is published
during the content render. It is not: what is published during the render is
the `.onHover` *registration*. The **invocation** is a mouse event, and events
are dispatched before the frame begins — `statusBar.height` is read at
`RenderLoop.swift:451`, well after `mouseEventDispatcher` has processed
whatever arrived. Focus works the same way (a key event), and so does the
delay expiring (a scheduled wake, which lands between frames).

So at the moment the height is computed, the frame already knows: whether a
tooltip is showing, what its text is, and — since the bar's width is the
terminal's — exactly how many lines it wraps to. One pass, correct height, no
content shift, at one line or at four.

The one case that does lag is narrow and probably not worth solving: if the
help TEXT ITSELF changes while the tooltip is already up (the view re-renders
with a different string), the bar shows the previous string for one frame,
because the closure carrying it was registered last frame. A tooltip whose
text changes under a stationary pointer is not a case worth a second render
pass.

That leaves the two real choices as presentation questions rather than
plumbing ones:

| | content shift | wasted space |
|---|---|---|
| **Bar grows and shrinks with the tooltip** | the content area resizes as tooltips come and go | none |
| **Reserve the row always** | none | one row, forever |

Growing is the recommendation, because the shift is now *synchronous* with the
tooltip rather than a frame behind it — the content moves and the tooltip
appears in the same frame, which reads as one event. Reserving is the fallback
if that still feels unsettled in use, and it is a one-line change to the height
calculation rather than a different design.

Wrapping is ordinary text wrapping at the bar's width, and the row is drawn
above the shortcut items, in the bar's own chrome.

Growing moves more than the bar. A page laid out in the middle of the window
(a `WindowGroup` centres one that does not fill it) moves with the row, so the
view under a resting pointer slides out from under it as its tooltip shows.
Taken as the pointer leaving, that took the tooltip away, which gave the row
back, which slid the view under the pointer again and restarted the delay: a
help that flashed for one frame (decisions-HELP A-HELP-1). A reshape that the
bar's rows for a tooltip cause is therefore not a hover change to the
tooltip: the candidate is held, and shown, until the pointer moves and does
not land on its view again, or the view goes or is covered
(`TooltipState.held`). The controls and `.onHover` hear the pointer's
transitions as before. A page that fills the window does not move: the bar's
rows cover its last visible rows, and the view under the pointer with them.
A pointer resting on the rows the bar took for its tooltip still counts as on
the tooltip's own view, so the help stays there too
(`WindowChromeState.tooltipRows`), until a sheet, docked or not, an alert, a
popover or a menu is presented over the page (`TooltipState.heldPresentations`).

Growing has one consequence below the layout. The bar grows *upwards*, so its
top edge moves a row with every tooltip that comes or goes — and the frame
diff compares a region's rows by index from wherever the region is written.
The bar's top border, the same bytes either side of the move, compared equal
and was skipped: a blank row where the border belonged as a tooltip appeared,
and the tooltip's text left standing there as it went. The run loop therefore
invalidates the diff whenever the bar's start row changes, not only when the
bar appears or disappears (`RenderLoop.noteStatusBarPlacement(startRow:)`).

## 5. Presentation 2 — a popover

Attached to the **control**, not the pointer. The placement rules, in order:

1. Prefer **below** the control, left-aligned to it.
2. If it does not fit below, **above**; then to the **side**.
3. Never overlap the control itself.
4. Prefer a position that does not sit under the **pointer** — but only after
   1–3, because full visibility beats getting out of the way.
5. Never truncate. If no placement fits the text without truncation, the text
   wraps to a narrower box before any placement is rejected.

This is `DropdownMenuRenderer`'s problem with one extra constraint, and that
renderer already solves flipping and clamping (`OverlayLayer.placed(maxWidth:maxHeight:)`).
The popover reuses it.

It **cannot take focus** and must not move focus when it appears or
disappears — it is not in the focus ring at all, which is simply not
registering. It **dismisses on any click**, as the escape hatch for the case
where it is in the way despite rule 4.

### Many panels at once (built 2026-10-12)

Under `.always` every `help(_:)` draws its panel, and the shared rule placed
each as if it were alone: measured on 2026-10-12, a `Button`'s panel covered a
`Text`'s. Those panels are now placed as a set, at the screen root, where all of
them are known (`OverlayLayer.arrangingPeers`, from `compositingOverlays`; each
panel carries an `OverlayLayer.peerPlacement` naming the view it describes).
One at a time, in a fixed order, each takes a place that:

- is beside its view: below or above it sharing a column, or to its right or
  left sharing a row and no further off than the panel is wide;
- is on screen, and covers neither its own view (rule 3) nor a panel already
  placed;
- of those, covers the fewest cells of the other views with help, then the
  fewest of the places the panels still to come would take first, then comes
  first in rules 1–2's order (below, above, right, left, each nearest the spot
  aligned with the view).

The order is the hovered view's panel, then the focused view's, then the rest
in **reading order** of their views (top to bottom, left to right), so the
same page draws the same panels whatever order its views were built in. A
panel with no such place is **left out**, not drawn over another: two
half-covered panels read worse than one whole one. Because the hovered and
focused views go first, pointing at a view (or focusing it) brings back a
panel that lost its place. The look-ahead (the places later panels want) is
what keeps every panel in a column of one-row views: without it the first
panel took the right-hand side of the rows the second needed.

What this still does not do: rules 4 and 5 (a panel arrives at the root drawn,
and its text does not, so it cannot be re-wrapped there), and a panel inside a
presentation is placed with the others in that presentation, not with the
page's beneath it. A panel inside a view's displaced drawing (`.offset`,
`.position`, a transition under way) is the page's, though it rides in that
drawing's own layer: it is placed with the page's panels, where the layer
will put it. Found by review: placed alone when its layer composited, it
went over the page's panels, and theirs over its view.

## 6. API

```swift
extension View {
    public func help(_ text: LocalizedStringKey) -> some View
    public func help(_ text: Text) -> some View
    public func help<S: StringProtocol>(_ text: S) -> some View     // SwiftUI's three

    public func tooltips(_ trigger: TooltipTrigger) -> some View        // see below
    public func tooltipStyle(_ style: TooltipStyle) -> some View          // .statusBar/.popover
    public func tooltipDelay(_ seconds: Double) -> some View
}
```

Three overloads because SwiftUI has three; the rest are TUI-specific and go
through the environment like every other subtree setting, so an app can turn
tooltips off for one panel.

`TooltipTrigger` is one axis ordered by eagerness rather than two flags, because
no combination of "whether" and "when" is meaningful:

| case | shows |
|------|-------|
| `.never` | nothing. `help(_:)` still compiles and still publishes. |
| `.automatic` | on hover after the delay; on the help key for the focused view. |
| `.onFocus` | …and whenever a control takes the focus, after the same delay. A beginner mode. |
| `.always` | every tooltip in the subtree, all at once, as popovers. A first-launch tour. |

`.always` forces the popover presentation whatever `tooltipStyle` says, because
the status bar has one row and this mode has many tooltips. The override travels on
the *candidate* rather than being applied by the run loop, for the reason
`Candidate.style` exists at all: `tooltipStyle` is a subtree setting and the run
loop has only the root environment to read. Without it the bar would show the
hovered tooltip as a second, redundant presentation of a panel already on screen.

Panels under `.always` avoid one another and the views they describe (§5, "Many
panels at once"). On a page too dense for all of them some are left out; the
hovered and the focused view's panels are placed first.

## 7. Open questions for the owner

1. **A view with help AND a status-bar verb.** The bar already carries a verb
   from the focused control ("↵ choose"). Does the tooltip row displace it,
   sit above it, or only show when there is no verb? The row is above the
   shortcuts, so *both* is the natural reading and is what this assumes.
2. **Nested help.** `help` on a container and on a child inside it: innermost
   wins, as with every other cascade — but a hover over the child is also a
   hover over the container, so this is a rule rather than an accident.
   *Built so on 2026-10-18:* both hear the pointer (every hover observer in
   front of the control does), and the innermost is the candidate
   (`TooltipState.observersHovered`); leaving the child for the rest of the
   container shows the container's help, its delay already served. Until then
   hover resolved one observer per point, the outermost, so the container's
   help showed over the child and the child's never did.
3. **A non-focusable view with no hit region.** `.onHover` establishes one, so
   `help` on a `Text` makes that `Text` hit-testable where it was not. That is
   a small behavioural change to anything sitting under it.

## 8. Staging

1. `TooltipState` + `HelpModifier` + `help(_:)`, publishing to nothing.
   Testable on its own: does the right text become the candidate, does hover
   beat focus, does the delay hold it back?
2. `focus(id:reason:)` and the five call sites — its own commit, since it is
   useful on its own and its risk is unrelated.
3. Presentation 1, with the two-pass height. Evaluate.
4. Presentation 2, on the overlay placement machinery.
5. The Example demo, which is also where the presentations get compared.
   Built 2026-10-12: the Help & Tooltips page (`Example --page help`, menu key
   `h`) has a `Button`, a `Toggle`, two `Text`s and a `TextField` with help,
   and pickers for the presentation and the trigger, `.always` included,
   which is also how a keyboard reader sees the two `Text`s' help there.
