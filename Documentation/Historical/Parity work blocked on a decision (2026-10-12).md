# Parity work blocked on a decision

*Historical (moved here 2026-10-15): the last entry was answered and built on
2026-10-12, leaving the file empty, as its own review below says. Kept for the
reasoning recorded in its answered-so-far paragraph; questions for the owner now
go in each lane's decisions file under `Documentation/SwiftUI parity/Decisions/`.*

SwiftUI APIs that `Tools/APIParity` reports as gaps, where the gap is **not** a
matter of effort. Each needs a call that changes what existing TUI code does,
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

Last reviewed: 2026-10-12. **No question is left, and no entry.** The last,
§1 (`View.help(_:)`), shipped on 2026-09-09; the owner answered its remaining
question on 2026-10-12 (views that cannot take the focus have help too, by
hover and by an app-wide help feature), and lane HELP built that the same day:
[Tooltips and help in a terminal](<../Controls and presentation/Tooltips and help in a terminal.md>)
and [decisions HELP](<../SwiftUI parity/Decisions/Presentation and windows/Help on views that cannot take the focus (HELP).md>).
The two opacity entries went by being built. With nothing left in it, this file
moved to `Historical/` on 2026-10-15.

**An entry ends in a recommendation.** It is a recommendation, not a decision:
the point of this file is that the call is not mine to make. But an option list
with no opinion attached is a worse thing to be handed than one with an opinion
you can disagree with.

---

## Recording the answers

An answered item should end in one of two places, not in this file:

- **Implemented** — with the reasoning in the commit message, and
  `Tools/APIParity/api_parity.py --accept` re-run so the gap count moves.
- **Declined** — as an entry in `Tools/APIParity/parity-map.json` under
  `notImplemented` or `differentShape`, with the `why`. `--stale` will then keep
  that entry honest if the code later changes underneath it.
