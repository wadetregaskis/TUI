# Parity work blocked on a decision

SwiftUI APIs that `Tools/APIParity` reports as gaps, where the gap is **not** a
matter of effort. Each needs a call that changes what existing TUIkit code does,
or picks between two defensible meanings. Implementing one of these without the
decision would be guessing on the owner's behalf, so they are parked here rather
than shipped.

Everything *not* on this list is ordinary work and is being done.

**Answered so far:** §1 (`opacity:` initialisers) and §2 (`Color.clear`) were
both **answered by building them**, on 2026-09-10: `Color` carries a real alpha,
resolved at the composite against what is actually behind the cell. The entries
are gone rather than ticked, as this file's last section requires; the design and
what it does NOT yet cover are in
[`Opacity as composition.md`](<../Colour and styling/Opacity as composition.md>). Also: §9 (`Text.bold(_:)` and its siblings) — resolved by taking
its option (a): `TextStyle`'s five cascaded flags became tri-state, the merge
became nearest-wins, and the parameters followed. §6 (`labelsHidden()`) and §7
(`deleteDisabled`/`moveDisabled`) were both implemented after the last review —
`LabelsVisibility.swift` with `_CollapsingLabel`, `ColorPicker`, `Toggle`,
`ProgressView` and `DatePicker` all honouring it, and
`RowEditRestrictionModifiers.swift` with `RowEditRestrictionTests`. §1
(`Color.primary`/`.secondary`), §2 (`Color.accentColor`) and §8
(`focusEffectDisabled`) were answered on 2026-08-24. The colours were
implemented together: the whole "Semantic Colors" block now
means the palette roles it is named after, and the SwiftUI spelling replaced
`Color.accent`. `focusEffectDisabled` took the strict reading — every focus
indication goes, not only the animated part — with the caret and the
`DatePicker`'s field marker surviving as insertion points rather than
announcements, gated through one `RenderContext.indicatesFocus(_:)` so it
cannot be honoured by some controls and forgotten by others. The
reasoning is in those commits; the entries are gone from here rather than
marked done, as this file's last section requires.

Last reviewed: 2026-10-12. **No question is left.** The last entry, §1
(`View.help(_:)`), shipped on 2026-09-09 and its remaining question was
answered by the owner on 2026-10-12; it stays below, marked, only until the
lane that ruling asks for lands. Then this file has nothing left in it and
moves to `Historical/`. The two opacity entries went by being built.

**The entry ends in a recommendation.** It is a recommendation, not a decision:
the point of this file is that the call is not mine to make. But an option list
with no opinion attached is a worse thing to be handed than one with an opinion
you can disagree with.

---

## 1. `View.help(_:)` — what a tooltip means with no pointer

**Answered; lane owed.** `help(_:)` shipped on 2026-09-09 (aaa61874f and the
commits after it; [`Tooltips and help in a terminal.md`](<../Controls and presentation/Tooltips and help in a terminal.md>)): both presentations, a status
bar row above the key hints that grows upwards, and the popover, chosen by the
app; the `?` key reveals the focused control's help. Both questions below were
settled then: the bar took a row of its own above the items (question 1), and
a `Text` with `help(_:)` became hoverable (question 2). **The owner ruled on
2026-10-12 that `help(_:)` must work on views that cannot take the focus, by
mouse hover and by an app-wide help feature.** Measured that day (session
notes `MISC12/notes.md` §3, a headless app over the real run loop):

- Hover on a non-focusable `Text` works, in both presentations.
- The app-wide feature today is `.tooltips(.always)`, which an app sets. It
  draws a non-focusable view's help too, but the panels are placed
  independently and overlap: a `Button`'s covered a `Text`'s.
- No keyboard route reaches a non-focusable view's help: `?` and `.onFocus`
  act only on the focused control.
- Two defects in the focus path, both from a per-walk reset that runs before
  the status bar is resolved: a focus-revealed tooltip never reaches the
  status bar, the default presentation, so `?` shows nothing there; and
  `.onFocus` with any delay above zero never shows, because the delay restarts
  every frame. The unit tests drive `TooltipState` directly, so neither
  showed.

The lane owed: fix both defects first, with tests that drive the run loop for
each presentation and trigger; then an app-wide route to every view's help,
either `.always` panels that avoid one another (built 2026-10-12:
[Tooltips](<../Controls and presentation/Tooltips and help in a terminal.md#many-panels-at-once-built-2026-10-12>) §5)
or a keyboard "help browse" mode that steps through every view with help, one
tooltip at a time, whose key is the owner's to choose; and the Example page
`Tooltips and help in a terminal.md` §8 planned, which was never built. The text below is the
question as it stood on 2026-09-10.

**The gap.** `help(_:)` in its `LocalizedStringKey`, `Text` and `StringProtocol`
overloads.

**Why it needs a decision.** A terminal has no hover tooltip. The plausible
surface is the **status bar** — "the focused view's help text appears there" —
which is a genuine UX decision about what that bar is for, not a mechanical port.

**Also needs work either way.** `FocusRegistration` is not quite the universal
seam it looks like: the split divider registers with the focus manager directly
(`NavigationSplitView.swift:554` and `:569`). It is the only site left — this
entry named `Button` too, wrongly: `Button` has gone through the seam since
`e2474a54` (2026-02-13), at `Button.swift:354`. Any help-on-focus mechanism
routed only through `FocusRegistration` would work for every other focusable
and silently not for that one — the failure mode already declined twice on this
list, at one site instead of a class of them.

**Found 2026-08-24: most of the mechanism already exists.** The status bar
already carries a string contributed by the focused control —
`StatusBarState.activationLabelOverride`, written by
`FocusRegistration.swift:180` and read by `StatusBar.swift:216`. "The focused
view's help text appears in the status bar" is therefore not a new surface; it
is a second writer of a slot that already has one.

That converts the open question from "what is the status bar for" into two
smaller and much more answerable ones:

1. **What happens when a control has both?** The existing override is a VERB —
   what Return will do ("choose", "open", "select"). A help string is a
   description. They are different things and both are useful, so either the
   bar grows a second slot, or help wins while focused and the verb returns
   when there is none, or help is shown only when the control offers no verb.
   The third is the cheapest and reads worst — the controls most worth
   documenting are the ones that do something.
2. **Does `help(_:)` on a NON-focusable view do anything at all?** SwiftUI
   attaches tooltips to anything. If the answer is "only focusables", then
   `help(_:)` on a `Text` compiles and silently does nothing, which is the
   failure mode this list keeps declining.

**Recommendation: (1) a second slot, and (2) yes-but-inert-is-not-acceptable.**
Concretely: implement `help(_:)` only if it is honoured for every focusable —
which means fixing the two direct registrants first, as its own commit — and
record it as `notImplemented` in the parity map until then, with the reason
being (2) rather than the status-bar question, which is now answered.

---

## Recording the answers

An answered item should end in one of two places, not in this file:

- **Implemented** — with the reasoning in the commit message, and
  `Tools/APIParity/api_parity.py --accept` re-run so the gap count moves.
- **Declined** — as an entry in `Tools/APIParity/parity-map.json` under
  `notImplemented` or `differentShape`, with the `why`. `--stale` will then keep
  that entry honest if the code later changes underneath it.
