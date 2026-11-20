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
- **Switch on private vulnerability reporting** (SECURITY, 2026-11-09): the repository's *Settings → Security →
  Private vulnerability reporting*. `SECURITY.md` already sends reporters there; until it is on, the link it gives
  leads nowhere.

## Decisions waiting on you

### Open on 2026-11-19

Answered the same day, and built: **attralign**, "(a) but provide our own version anywhere that Core Text doesn't
(e.g. macOS 15) if possible". On the macOS 26 SDK a paragraph's `alignment` is Core Text's own, macOS 26 only as in
SwiftUI, and never ambiguous to name; TUI declares the same names only where no SDK does (the macOS 15 SDKs, Linux,
Windows); and TUI's own `paragraphAlignment` aligns a paragraph on every macOS, 15 included, under a name SwiftUI
does not use ([the G3 design](<Historical/Text, editing and the clipboard/An attributed TextEditor - design (G3).md>)
§5 and §7). What it left:

| Id | Question | Recommended | If you don't answer |
|---|---|---|---|
| A-ATTRED-13 | A paragraph's line height. Core Text's `LineHeight` factor has no accessor, and the ways to read it (`==` against a grid of made values, its undocumented Codable encoding, reflection) cannot run on this macOS 15 machine. (a) a TUI-named attribute only, every platform and macOS, ¼ day; (b) (a) plus SwiftUI's `lineHeight` read by `==` on a grid, ½ day and a macOS 26 CI run; (c) (a) plus `lineHeight` read through its encoding, ¾ day, a CI round trip to learn it and a test pinning it; (d) not yet. Each adds 1 to 1½ days of editor work ([the G3 design](<Historical/Text, editing and the clipboard/An attributed TextEditor - design (G3).md>) §6) | (a) if an app wants it; (b) on top only if a SwiftUI program's `lineHeight` matters; else (d) | (d) |
| A-ATTRED-14 | On the macOS 26 SDK the scope's `alignment` is computed, not stored, because a stored property cannot be newer than its type outside library evolution. So a coder or Markdown parse given `\.swiftUI`'s scope leaves a paragraph's alignment out there, where SwiftUI's carries it (believed, not measured: it needs macOS 26). Recorded as deviation T14 ([Deliberate deviations](<SwiftUI parity/Deliberate deviations from SwiftUI.md#t14-a-paragraphs-alignment-is-not-among-the-swiftui-scopes-stored-keys-on-the-macos-26-sdk>)). Approve it, or ask for a workaround (none known) | Approve | It stands as recorded |

EXPERIMENTS (API-STABILITY point 5), open since 2026-11-09, is answered: the last experiment,
`TUI_PLAIN_TEXT=transliterate`, was promoted to a supported option on 2026-11-19, and none is left. The record is in
[2026-11-08](<Historical/SwiftUI parity process/The owner's decisions of 2026-11-08.md>).

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
