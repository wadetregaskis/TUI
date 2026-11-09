# Open owner decisions

What is waiting on you, the open questions re-checked on 2026-11-02 against `main`. Only open questions are kept
here (since 2026-11-08); every answer, with the owner's words and what it changed, is in the decision records in
`Historical/SwiftUI parity process`:
[2026-10-18 to 2026-10-25](<Historical/SwiftUI parity process/The owner's decisions, 2026-10-18 to 2026-10-25.md>)
(with the answers of 2026-10-26), [2026-10-27 to 2026-11-07](<Historical/SwiftUI parity process/The owner's decisions, 2026-10-27 to 2026-11-07.md>)
and [2026-11-08](<Historical/SwiftUI parity process/The owner's decisions of 2026-11-08.md>) (with the evening page
answered on 2026-11-09). None of these blocks
other work: each has a default, which holds until you answer.

Answer by id and option ("B75: a"); a bare "yes" takes the recommendation.

## Owner actions

- **B-F2-4, once in Ghostty:** run `IDLE_PROBE_MODE=hang ~/Library/Caches/tuikit-probe/owner-keys/IdleProbe`
  (a release `IdleProbe`, staged there because Ghostty may not open files under `~/Documents`), press ⌃\\
  once, wait about two seconds, and press it again: the app should quit at the second press, the terminal
  restored. Under the kitty keyboard protocol ⌃\\ arrives as a key report, and only the stall watchdog
  makes a hung app quit.
- **Animated pictures:** run `python3 Tools/TerminalProbes/animation_probe.py` in Ghostty. Its result decides whether a
  terminal playing an animated picture by itself (`TUI_GRAPHICS_PLAYBACK`, off today) goes on by default.
- **Push `main`.** Local `main` is ahead of GitHub (189 commits on 2026-11-08; last pushed 2026-11-06,
  `16dfc440f`).
- **Compiler bug reports** on the Desktop, one file per bug, are yours to file.
- **Push, then run the SwiftUI-27 parity job once** (SDK-27, 2026-11-09): after pushing `main`, *Actions →
  SwiftUI parity (Xcode 27) → Run workflow* with the defaults. It compares TUI with Xcode 27's SwiftUI on GitHub's
  `xcode-27` image and keeps the report as the run's artifact, which I read with the read-only token. Until then the
  comparison runs against Xcode 26.3's SDK, and MACOS27-PARITY waits on it.
- **Switch on private vulnerability reporting** (SECURITY, 2026-11-09): the repository's *Settings → Security →
  Private vulnerability reporting*. `SECURITY.md` already sends reporters there; until it is on, the link it gives
  leads nowhere.

## Decisions waiting on you

### Open on 2026-11-08

| Id | Question | Recommended | If you don't answer |
|---|---|---|---|
| API-STABILITY | What 1.0 promises about the public API, and how deprecation and minimum versions work after it: [the draft](<API stability policy (draft).md>), with eleven decisions in its last table. Still open on 2026-11-09: you will answer the eleven points, in the draft or in chat. | Its recommendations | Nothing is promised; the pre-1.0 rules stand |

### Open on 2026-11-01

| Id | Question | Recommended | If you don't answer |
|---|---|---|---|
| SCROLL-REGIONS | Moving rows with a scroll region rather than rewriting them: 28.6% fewer bytes over the sessions, no noticeable cost, on every terminal measured ([the study](<Performance/Scroll regions for output.md>)). On by default at the `exact` level, after you have watched one scroll on Apple Terminal? Keep or drop `residue` and `margins`, which add 1.4 points? | On, `exact`; drop the other two for now | Stays off, on its branch |
| PARTIAL-TUI | A grid at the foot of the terminal, scrollback above ([the design](<Partial TUI.md>)): about 13 commits. It suits tools rather than page apps, and helps accessibility only a little. Build it after 1.0, or sooner? | After 1.0; the real cursor and "still" first if accessibility is the reason | After 1.0 |
| HR-1 to HR-6 | Compiled hot reload, for when it's picked up: [section 10 of the design](<Compiled hot reload.md#10-what-the-owner-decides-when-this-is-picked-up>). | The design's defaults for HR-1 to HR-5 | Waits; nothing is built |

### Open on 2026-10-28

| Id | Question | Recommended | If you don't answer |
|---|---|---|---|
| SCROLLBAR-PLACEMENT | Try `.overContent` before the final say: the Example's Theme page now switches it (Scroll indicators). Hover a list, then click it: the bar moves from over the rows to beside them. | — | Both stay, beside the content by default. |

## New on 2026-10-25

- **The README's hero clip.** You haven't chosen. Candidates filmed or sketched: the system monitor,
  now playing, the weather; the 10-24 pick was the slider driving a gauge.
- **The Animation clip** is settled (2026-10-26): it keeps ordinary view animation, and the photo zoom
  went into the Navigation clip.
- **Environment variables** (answered 2026-10-27: rename): every `TUIKIT_` variable is `TUI_` now.
- **The page behind a sheet** is now veiled rather than flattened (your ruling of 2026-10-25), with a
  cost of +6.4% on a frame with a sheet open in the notes session, and a gain of 11.8% in another. Its
  strength is now 25% kept with 60% of the colour out (your pick of 2026-10-28, "25d60").

## Deferred, by your choice

- **DORMANT-DESIGNS**: after the SwiftUI API compatibility work.
- **MACOS27-PARITY**: when a macOS 27 machine is available; for the API comparison, when the SwiftUI-27 parity job
  (an owner action above) has run.
- **OOB-STYLING**: explore along (a) later; a reminder when the queue runs out.
- **A-D6L-1**: a reminder at the end of the queue.
- **BINARY-DISTRIBUTION**: two compiler bug reports are on the Desktop; the rest waits on them.
- **Right-to-left text**: wanted, after the SwiftUI API compatibility work (2026-10-12).
