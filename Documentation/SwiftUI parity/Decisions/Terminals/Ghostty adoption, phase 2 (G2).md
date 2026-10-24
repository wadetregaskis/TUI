# Ghostty adoption, Phase 2: decisions for review

*The G2 lane's companion to
[`SwiftUI API completion decisions.md`](<../SwiftUI API completion decisions.md>),
in its format, for the Phase 2 steps of
[`Ghostty VT reference adoption study.md`](<../../../Terminals/Ghostty VT reference adoption study.md>) §6 (V1 to V5).
2026-10-05.*

- **A. Needs your decision.** None.
- **B. Shipped the safe option.** Four.
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

### B-G2-2. Autowrap is off everywhere but Apple Terminal, which waits for its card

*V5 (K3).*

**Shipped:** `CSI ? 7 l` from startup (and on resume) on every host but Apple
Terminal; `CSI ? 7 h` on every way out and in the fatal-signal debt, on every
host (harmless where it was never turned off). The plan makes a card session on
Apple Terminal the precondition, because its right-edge phantom repaint
(`FrameDiffWriter.repaintRightEdge`) and its clip's peak guard were written
against a row that wraps, so Apple Terminal keeps the terminal's default
(`Terminal.keepsAutowrap`): named by the environment, it is never sent `?7l`;
reached over ssh, it is sent `?7h` as soon as the startup exchange names it,
before the first frame. (The first cut of this step shipped `?7l` to Apple
Terminal too; review found that its clip lets an over-advancer's peak end on the
last cell, where with autowrap off the cursor is pinned and the `CUB` repair
lands one column short.)

**The fuller version:** the cards (`Terminal compatibility survey.md`, "Autowrap off
while the app runs": an over-wide last row on Apple Terminal light and dark,
with `?7l` sent by hand, then iTerm2 with ambiguous-wide on, Ghostty, Warp,
kitty and tmux). If Apple Terminal behaves, dropping `keepsAutowrap` turns it
on there, and its clip must then stop an over-advancer's peak short of the
last cell; if its phantom cells no longer appear, the repaint and its per-row
overdraw can go. About half a day after the cards.

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

### B-G2-4. A terminal left non-blocking is waited on as long as a blocking write would wait

*Review of V2 (O1).*

**Shipped:** a frame write that meets `EAGAIN` (a terminal a crashed program
left `O_NONBLOCK`) polls for room and carries on, with no deadline
(`Terminal.writeAll`, `waitForRoom(on:until:)`). That is exactly what a
blocking write, the normal case, does: it never gives up on a terminal that
reads slowly, and it hangs on one that stops reading, as TUIkit always has.
The review suggested a short deadline before the end marker's retry.

**The alternative:** a deadline, about ten minutes' work. It would keep the app
responsive while a terminal is not reading, at the price of a torn frame and,
for a held one, an end marker that cannot be sent either, which is the freeze
the change removes. Worth it only if a terminal is found that stops reading
for long while the app should go on running.
