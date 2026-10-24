# Ghostty adoption, Phase 1: decisions for review

*The G1 lane's companion to
[`SwiftUI API completion decisions.md`](<../SwiftUI API completion decisions.md>),
in its format, for the Phase 1 steps of
[`Ghostty VT reference adoption study.md`](<../../../Terminals/Ghostty VT reference adoption study.md>) §6 (G1 to G4 and M0).
2026-10-05.*

- **A. Needs your decision.** None.
- **B. Shipped the safe option.** Two, both about measuring O2 and O3.
- **C. Declined without asking.** None.

## B. Shipped the safe option

### B-G1-1. The band-scroll estimate runs, and today's scenarios cannot answer it

*O2 (hardware scrolling) and your question Q5: spend 3–5 days on it if the
estimate shows at least 50% fewer bytes on `scroll` and `list`.*

**Shipped:** the tool. `analyze_stream.py --shift` replays a `drive.py` dump
step by step and prices the best band shift per step: once with exact bands,
as O2 is specified, and once letting a row differ from its source in up to
four cells that are repainted after the shift (a scroll view's own indicator
column). `--runs` prices O3's four trims.

**What it found, as an indicative capture** (debug build, a loaded machine;
numbers in M0's commit message): 0% for the band scroll on all five
scenarios, both ways. That says more about the scenarios than about O2. None
of them scrolls a full-width band:
- `scroll`'s views are bordered boxes seven rows tall with an indicator
  column;
- `table`'s file browser shows five rows;
- `list` scrolls nothing at all. The Lists page now opens with the focus in a
  search field, so the scenario's Down keys move nothing, and its bytes after
  the first frame are a blinking caret.

So the 50% bar in Q5 cannot be met or missed by these five.

**The fuller version:** a scenario with a tall, full-width list scrolled a row
at a time, which Example does not have on any page today. Either a page
section (a `List` of a few hundred rows filling the page) and a `drive.py`
scenario for it, or a scenario on Stress's `megalist`. About half a day, then
the coordinator's quiet-box capture. Until then O2 stays where the study put
it: a hypothesis.

### B-G1-2. `drive.py` answers the startup status request only when asked to

*`drive.py --answer-fence`.*

A PTY answers nothing, so a TUIkit app's identity, graphics and colour
exchanges each wait out half a second and the first frame comes about 1.5 s
after launch. A scenario's keys sent before then are handed back and parsed as
one burst once the app is up: on a debug Example, `scroll` drew its page for
the first time at step 83 of 93. A `drive.py` byte count taken since the three
startup exchanges existed may share that artefact; which ones do is not
established. The `scroll` baseline the study quotes (45,264 bytes) is close to
what the debug Example writes with the fence answered (42,260), so it may
predate the exchanges.

**Shipped:** `--answer-fence`, off by default, which answers `CSI 5n` with
`CSI 0n` as every terminal does. Off so that a number taken before the flag
existed stays comparable with one taken after. The README's M0 recipe passes
it.

**The alternative:** answer by default, since every real terminal does, and
re-take the baselines once. It costs nothing to switch; the price is that
every older `drive.py` number in the docs stops being comparable.
