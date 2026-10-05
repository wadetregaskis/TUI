# Ghostty adoption, Phase 2: decisions for review

*The G2 lane's companion to
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md),
in its format, for the Phase 2 steps of
[`Ghostty-VT-adoption.md`](Ghostty-VT-adoption.md) §6 (V1 to V5).
2026-10-05.*

- **A. Needs your decision.** None.
- **B. Shipped the safe option.** Three.
- **C. Declined without asking.** None.

## B. Shipped the safe option

### B-G2-1. Synchronized output goes to every host, asked of none

*V2 (O1): `CSI ? 2026 h` / `l` around every frame that writes more than one
row.*

**Shipped:** the markers are sent to every host, Apple Terminal and
unidentified hosts included, with `TUIKIT_SYNCHRONIZED_OUTPUT=0` as the user's
off switch. That is the study's plan: the `?`-without-intermediate shape was
measured clean on all four hosts, a host without the mode ignores it, and
setting the mode needs no answer. Nothing is asked at run time. DECRQM
`?2026$p` is the shape Apple Terminal prints, so it is asked only by the new
`sync_probe.py`, and there only of a host that identifies itself (a
`TERM_PROGRAM` naming a non-Apple host, or an XTVERSION answer, which Apple
Terminal never gives).

**The fuller version:** gate per host once `sync_probe.py` has run: skip the
markers where the host is known to ignore them (most likely Apple Terminal),
saving 16 bytes per multi-row frame there, and ask DECRQM `?2026` on the
exchange Ghostty already gets for mode 2027 at no extra round trip. About two
hours. The saving is small (0.8% of the tour's bytes), so this is worth doing
only if a probe finds a host that takes the markers badly.

### B-G2-2. Autowrap is off everywhere before the over-wide last-row cards

*V5 (K3).*

**Shipped:** `CSI ? 7 l` on every host from startup (and on resume),
`CSI ? 7 h` on every way out and in the fatal-signal debt. The study asks for a
card session on Apple Terminal first, because its right-edge phantom repaint
(`FrameDiffWriter.repaintRightEdge`) was written against a row that wraps. The
repaint writes by absolute position, erasing and redrawing the last two cells,
so it does not depend on wrapping and should be harmless overdraw at worst; an
over-advancing cluster at the edge now clamps on its own row instead of
wrapping into the next or scrolling the screen.

**The fuller version:** the cards (`Terminal-compatibility.md`, "Autowrap off
while the app runs": an over-wide last row on Apple Terminal light and dark,
then iTerm2 with ambiguous-wide on, Ghostty, Warp, kitty and tmux). If Apple
Terminal's phantom cells no longer appear with autowrap off, the repaint and
its per-row overdraw can go: about half a day after the cards.

### B-G2-3. The keypad's Tab and Space carry the numeric pad in their SS3 spelling

*V4 (K1).*

**Shipped:** `ESC O I` and `ESC O space` (xterm's keypad Tab and Space) decode
as Tab and Space with `.numericPad`, like every other application-keypad key.
Every other keypad key decodes to exactly the event the kitty protocol's report
of the same key does (pinned); these two have no kitty keypad code, so under
the protocol the same physical key would arrive without `.numericPad`. Mac
keyboards have neither key, so this is a choice about other keyboards only.

**The alternative:** decode them without `.numericPad`, matching what the
protocol would deliver. Five minutes either way.
