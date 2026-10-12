# Completing the SwiftUI API: decisions from lane HELP

*Lane HELP, 2026-10-12, built what the owner asked for that day: "`View.help(_:)`:
non-focusable views should support it, too. At the very least they can show
the tooltip when hovered over by the mouse. [...] let's at least get them
working with the mouse and any 'app-wide show-help' feature we might already
have." Hover already worked on a `Text`. The app-wide feature is
`.tooltips(.always)`, whose panels now avoid one another. Two defects in the
focus path were fixed first (the help key showed nothing in the default
status-bar presentation, and `.onFocus` never showed after a delay). The
measurements behind it are in the session notes, `MISC12/notes.md` §3, and
`Controls and presentation/Tooltips and help in a terminal.md` is the spec.*

*The format is that of
[`SwiftUI API completion decisions.md`](<SwiftUI API completion decisions.md>):*

- **A-HELP-n — needs your decision.**
- **B-HELP-n — shipped the safe option.** Says what the fuller version would
  be, and its price.
- **C-HELP-n — declined.** With the reason.

There is no C entry.

## A. Needs your decision

### A-HELP-1. A hover tooltip in the status bar flickers over a page laid out in the middle

**Found while pinning hover on a non-focusable view through the run loop**
(`HelpRunLoopTests.hoverOverACentredPage`, a `withKnownIssue` test; not
caused by this lane, and older than it). The status bar grows upwards for a
tooltip (Tooltips §4, "Bar grows and shrinks with the tooltip"), so the page
above it loses a row or more. A page laid out in the middle of the window
moves up with it; the view slides out from under the resting pointer; the
dispatcher re-resolves the hover after the reshape and reports `.exited`; the
tooltip goes, the page moves back under the pointer, `.entered` arrives, and
the delay starts again. Measured headless at 50 × 14 with the default style
and delay: the help is on screen for one frame in every 0.6 s. A page laid out
from the top (most pages: a title, then a scroll view) does not move and is
not affected, nor is the popover, which moves nothing; the research probe
looked at one frame and so saw it shown.

Options:

1. **Hold the hover through the tooltip's own reflow (recommended).** In a
   frame whose bar rows changed because of a tooltip, the hover transitions
   the reshape synthesises are not hover changes: the candidate stays, marked
   displaced, until the pointer next moves and does not land on its view
   again. No visual change, and it fixes the class (anything the bar's growth
   moves). About half a lane-day: `RenderLoop` marks the reshape around
   `setRegions`, `TooltipState` keeps the displaced candidate, the dispatcher
   reports real motion so it can be let go, and tests.
2. **Reserve the row always**, §4's own fallback: the bar keeps a tooltip row
   whether or not one shows. One row of every app's page, permanently, and a
   help text that wraps to two rows still moves the page.
3. **Draw a hover tooltip's bar over the foot of the page** instead of
   shrinking it. No shift, but it covers the page's last rows while it shows:
   a change to the presentation §4 chose. About half a lane-day.

## B. Shipped the safe option

### B-HELP-1. Under `.always` the panels are popovers whatever `tooltipStyle` says, and the bar lists nothing

The brief asked how the status-bar style should show `.always`'s many
tooltips: the hovered or focused one, or a list. Neither: `.always` keeps
drawing every panel as a popover (Tooltips §6, as before), and the panels now
avoid one another (§5, "Many panels at once"). Why not the bar:

- `.statusBar` is the **default** style, so most apps that turn on `.always`
  never chose the bar. A list there would make `.always` mean a different
  thing depending on a setting the app did not touch.
- The bar's rows are reserved **before** the walk that finds the views with
  help, so a list would be a frame late, and its height would move the page
  that decides which views are on screen: a list that resizes the content it
  lists.
- A list loses where each view is; the panels keep it.

The hovered view's and the focused view's panels are placed first instead
(`TooltipState.placementRank`), so on a page too dense for every panel,
pointing at a view or focusing it brings its panel back.

**Fuller version and price.** A legend: a short numbered marker drawn beside
each view with help and the texts listed against the numbers in the bar,
taking the bar's rows from last frame's list. About one to one and a half
lane-days, mostly the feedback between the list's height and the page.

### B-HELP-2. No keyboard route to a non-focusable view's help beyond `.always`

A keyboard reader reaches a `Text`'s help only while the app shows every panel
(`.tooltips(.always)`); `?` and `.onFocus` act on the focused control. The owner
punted a "help browse" mode, and it is not built. One route nearly falls out
now that the panels avoid one another: **`?` when the focused control has no
help** (today it falls through unconsumed, case C of MISC12 §3.2) **could show
the screen's panels, and `?` again hide them.** Not built here because it is
more than the key: the reveal must reach views stored in the render cache (a
screen-wide flag whose change clears what the memo kept), and the key may only
be consumed when there is help on screen to show, which needs every
`help(_:)` to register itself in a way that replays when its row is served
from the memo, as `requestFeature` does. About half a lane-day to one, with
tests; and whether `?` should take on that meaning is yours to say.
