# Completing the SwiftUI API: lane SIZEDOCS's decisions for review

*A companion to [`SwiftUI API completion decisions.md`](<../SwiftUI API completion decisions.md>),
written by the lane that committed the binary-size study of 2026-10-10 to
[`Documentation/Historical/Binary size study (2026-10-10)/`](<../../../Historical/Binary size study (2026-10-10)>)
and the SwiftUI probes that TUIkit's code cites to
[`Tools/SwiftUIProbes/`](<../../../../Tools/SwiftUIProbes>) (the owner, 2026-10-12:
"The SIZE3 report.md, README.md, and probe sources are fine to commit. 233 KB
is substantial but worth it"). It holds only what that work raised that was
not already decided: the same three parts as the main file.*

- **A. Needs your decision.** Nothing has shipped for these.
- **B. Shipped the safe option.** A basic, honest form is in; each entry says
  what the fuller version would be, and what it would cost.
- **C. Declined without asking.** Listed so they can be vetoed.

## B. Shipped the safe option

### B-SIZEDOCS-1. Two probe sets more than the inventory listed: D1S's second round and wave 12's

*`Tools/SwiftUIProbes/Sections and subview counting/`, `Tools/SwiftUIProbes/Animation curves, springs and keyframes/`*

**Asked:** the eight probe sets that the plan for moving the working notes
listed as cited by committed code (`DYNP/probe`, `DYNP/optional`,
`SKEY/probe`, `GUIDE/probe`, `GUIDE/probe2`, `D6L/probe`, `D1S/probe`,
`w10b/probe`; about 233 KB), committed, and every citation of them pointed at
the committed copy.

**Found:** the code cites two more sets by path, without the words "session
notes" that the inventory searched for:

- `D1S/probe2`, the D1S lane's second round (sections in forms and menus, a
  view of the app's own whose body is several views, deleting a multi-view
  `List` row): four files in `Sources` (`CompositeMembers.swift`,
  `FormContentExtraction.swift`, `MenuSections.swift`,
  `ListRowEditOwner.swift`), four test files, and two places in the D1S
  decisions.
- `w12/probe`, wave 12's animation probes (`UnitCurve`, `Spring`,
  `KeyframeTimeline`): `KeyframeCurve.swift`, three test files, and wave 12's
  entries in the main decisions file.

**Shipped:** both, in a commit of their own, so that it can be dropped:
57,071 B of sources and outputs (measured), the second round beside the
first in "Sections and subview counting", and wave 12's as "Animation
curves, springs and keyframes"; their citations in `Sources`, `Tests` and the
D1S decisions repointed. With it, nothing in `Sources`, `Tests` or `Tools`
names a probe by its path in the working notes (`MeshGradientTests.swift` says
lane 17m's are there, without one). The main decisions file still
cites both `w10b/probe/` and `w12/probe/` there: that file is yours to edit.

**Fuller version, shipped 2026-10-23 (lane DOCS2, the owner's ruling
B-SIZEDOCS-1 (a)):** the SwiftUI probes that only decisions files cite (waves
6b, 8a, 8b, 10 and 11a, lanes 17, 17d, 17g and 17m, D5G and DECB), and since
then W1's, FB16's, PARITYMISC's, INPUT's and O13's, committed the same way
without the pixel dumps, renders, built programs and module caches, and their
citations in Documentation, Sources and Tests repointed. It is 174 files and
539,073 B (measured): sources, text outputs and the notes' scripts, in 16
folders of `Tools/SwiftUIProbes/` with an entry each in its README. It is
larger than the 438,206 B in 189 files the entry priced, because the sets that
lanes added since (PARITYMISC, INPUT, O13, W1 with its review round, FB16's
36 KB) came with it. Left in the working notes: wave 17t's probes, which
nothing named in the ruling; and the notes the code and decisions cite that are
not SwiftUI probes (DYNV/notes.md and DYNV2/notes.md, O9/probe, O10/probe).
Lane 8b's probes write PNGs; the committed copies write them to
`NSTemporaryDirectory()` and not to the notes folder.
