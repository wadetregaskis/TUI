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

- **Compiler bug reports** on the Desktop, one file per bug, are yours to file.
- **Run the SwiftUI-27 parity job once** (SDK-27, 2026-11-09): *Actions → SwiftUI parity (Xcode 27) → Run
  workflow* with the defaults. It compares TUI with Xcode 27's SwiftUI on GitHub's `xcode-27` image and keeps the
  report as the run's artifact, which I read with the read-only token. Until then the comparison runs against Xcode
  26.3's SDK, and MACOS27-PARITY waits on it. Before 1.0: a mismatch it finds is free to fix now, and a major
  release after.
- **A Windows VM** (API-STABILITY point 9, 2026-11-09): Windows is to be fully supported at 1.0, and the port is
  done on a Windows VM. Say how it is reached when it is ready.
- **Switch on private vulnerability reporting** (SECURITY, 2026-11-09): the repository's *Settings → Security →
  Private vulnerability reporting*. `SECURITY.md` already sends reporters there; until it is on, the link it gives
  leads nowhere.

## Decisions waiting on you

### Open on 2026-11-09

| Id | Question | Recommended | If you don't answer |
|---|---|---|---|
| EXPERIMENTS | Each experiment, promoted, kept as a documented experiment, or deleted before 1.0 (API-STABILITY point 5, 2026-11-09: you'll test them first): `TUI_ARROW_FOCUS`, `TUI_CURSOR_FOLLOWS_FOCUS`, `TUI_PLAIN_TEXT=transliterate`, `TUI_GRAPHICS_PLAYBACK` (Ghostty 1.4.0 plays every panel of the animation probe right, seen 2026-11-09), and the held-press widening (A-TEXT2-1). The [API stability policy](<API stability policy.md>) leaves an experiment out of the promise until it is promoted. | Decide each after trying it | They stay experiments, unpromised; 1.0 waits for your call |

### Open on 2026-11-01

| Id | Question | Recommended | If you don't answer |
|---|---|---|---|
| PARTIAL-TUI | A grid at the foot of the terminal, scrollback above ([the design](<Partial TUI.md>)): about 13 commits. It suits tools rather than page apps, and helps accessibility only a little. Build it after 1.0, or sooner? | After 1.0; the real cursor and "still" first if accessibility is the reason | After 1.0 |
| HR-1 to HR-6 | Compiled hot reload, for when it's picked up: [section 10 of the design](<Compiled hot reload.md#10-what-the-owner-decides-when-this-is-picked-up>). | The design's defaults for HR-1 to HR-5 | Waits; nothing is built |

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
