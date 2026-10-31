# Adopting what Ghostty documents: synchronized output, autowrap, progress and attention

*How the owner's review of Ghostty's VT reference turned into changes: the
band-scroll estimate, synchronized output for every host, autowrap off,
keypad keys, a non-blocking terminal, progress bars and requests for
attention. Ids: B-G1-1 and 2, B-G2-1 to 4, B-GHOSTTY-1 to 8. The study is
live: [Ghostty VT reference adoption study](<../../Terminals/Ghostty VT reference adoption study.md>);
measured behaviour is in [Terminal compatibility survey](<../../Terminals/Terminal compatibility survey.md>).*

## In short

Synchronized-output markers go to every host; autowrap is off everywhere but
Apple Terminal; a terminal left non-blocking is waited on as a blocking write
would be. A progress report goes only to terminals documented to draw one
(Ghostty, iTerm2, tmux), resent every five seconds, the last view's winning;
a request for attention is a notification on Ghostty and iTerm2 and the bell
elsewhere. `\.terminalFeatures` is the run-time check.

## How it unfolded

**2026-10-04, the owner** asked for Ghostty's VT reference to be reviewed and
the applicable sequences adopted. The study proposed phases; lanes G1, G2 and
GHOSTTY built them (2026-10-18 to 19).

## The record

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

A PTY answers nothing, so a TUI app's identity, graphics and colour
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
reads slowly, and it hangs on one that stops reading, as TUI always has.
The review suggested a short deadline before the end marker's retry.

**The alternative:** a deadline, about ten minutes' work. It would keep the app
responsive while a terminal is not reading, at the price of a torn frame and,
for a held one, an end marker that cannot be sent either, which is the freeze
the change removes. Worth it only if a terminal is found that stops reading
for long while the app should go on running.

### B-GHOSTTY-1. A progress report goes only to a terminal documented to draw one

*V8 (C3): `.terminalProgress(_:)`, sent as `OSC 9 ; 4`.*

**Shipped:** sent to Ghostty, iTerm2 and tmux, each documented to take it,
and to nothing else (`TerminalClient.honoursProgressReports`), as the lane's
brief asked; `TUIKIT_PROGRESS=1` or `0` is the user's override either way.
Every host swallows an OSC it does not implement, so sending it everywhere
would also be safe, but kitty before 0.38 posted any `OSC 9` as a desktop
notification, a progress report's `4;1;50` included, and an unmodelled host
could do the same. Under tmux it is sent, and tmux decides who sees it: it
passes the bar on only to a client with the `progressbar` feature, which 3.7c
gives iTerm2 and not Ghostty, Apple Terminal or Warp (measured), as it does
with hyperlinks; it keeps the bar for the pane, and hands it to a client
that can draw it when one attaches (measured), so it is sent whoever is
attached. Whether the person sees it is B-GHOSTTY-4's
`\.terminalFeatures.showsProgress`, which under tmux asks tmux.

**The fuller version:** kitty, which draws the bar from 0.47.0, recognised by
its `TERM` and its XTVERSION answer's version, so an old kitty is never sent
one: about an hour, plus a run on a kitty that can open a window (this
machine's cannot).

### B-GHOSTTY-2. The bar is sent again every five seconds, an unmeasured interval

*V8 (C3): Ghostty removes a bar no program has updated for about fifteen
seconds.*

**Shipped:** while a bar is up it is sent again whenever it has gone 5 s
unsent, a third of Ghostty's limit, to every host that is sent one but tmux:
from a frame that is drawn anyway, or between frames by the run loop, which
wakes for it and draws nothing (`TerminalHostState.keepAlive(atNanos:)`,
`FramePacer.waitNanos(now:pollingPendingInput:until:)`). That is a dozen bytes
every 5 s on a still screen with a bar up, and one wake of the loop. tmux
keeps a bar with no time limit and passes a report the same as the bar on to
no client (both measured), so a repeat would reach no terminal: it is sent
none. (The first version sent tmux one every 5 s as well; the lane's review
found it.) Inside tmux in a Ghostty given the `progressbar` feature, a bar
left unchanged for 15 s may therefore go, which only tmux could prevent.

**The fuller version:** measure each host's limit (`progress_probe.py
--timeout 20` and a look; tmux keeps a bar, measured) and send the keep-alive
only to a host that drops one, at a period measured against its limit. About
an hour after a probe session with Ghostty and iTerm2 on screen.

### B-GHOSTTY-3. The last view drawn that states progress wins

*V8 (C3): "resolved like a preference, so the last writer wins".*

**Shipped:** a preference whose last non-`nil` value wins: the innermost of
nested views, the last of siblings; a view stating `nil` leaves another's
standing, and the bar goes when no view drawn states one. A window held
behind the one in front, still drawn behind it, still states its progress
(pinned), so a long job in a window the person has covered keeps its bar:
the bar is the app's, as a Mac app's Dock tile is one per app, not per
window.

**The alternative:** combine what several views state, the least done winning
(two copies each at a different point), or the window in front's alone. Each
about an hour; neither has a use yet that the last-drawn rule fails.

### B-GHOSTTY-4. `\.terminalFeatures` is the run-time check, created here

*The A18 rule: an API that works only where the terminal supports it may
compile everywhere if there is a documented way to detect support at run
time. The study asked for one environment value, shaped like
`\.keyboardReporting`, that each terminal feature adds a field to.*

**Shipped:** `TerminalFeatures`, at `\.terminalFeatures`, with
`showsProgress`, whether the person sees the bar: published by the run loop
from the terminal identified at startup and the user's switches, and under
tmux from the clients attached, asked of tmux (`#{client_termfeatures}`, in
the `list-clients` it already runs to name them) at launch and again as
clients attach and detach, so it is `true` there only while every client
has the `progressbar` feature tmux passes the bar on by. `false` outside a
running app. (The first version said `true` under tmux whoever was attached,
and an app that drew its own progress only where the terminal shows none
showed none anywhere inside tmux in Ghostty, Apple Terminal or Warp; the
lane's review found it.)

**The fuller version:** the features shipped before it — whether OSC 8 links
are honoured, and whether a copy has a route to the person's clipboard —
moved into it as fields, so an app asks one value. About two hours, with their
tests.

### B-GHOSTTY-5. No app-level override

**Shipped:** only the user's environment variable overrides the table. An app
already chooses whether to use the feature at all, and `TerminalClient`'s
static overrides (`hyperlinkSupport`) are process-wide state this lane did not
want to add to.

**The fuller version:** `TerminalClient.progressSupport: Bool?`, in the shape
of `hyperlinkSupport`; half an hour.

### B-GHOSTTY-6. Attention is a notification on Ghostty and iTerm2, and the bell everywhere else

*V10 (C6): `\.requestAttention`, "OSC 9 where honoured and BEL otherwise".*

**Shipped:** `requestAttention(message)` posts iTerm2's `OSC 9 ; message` on
the two hosts documented to post it, Ghostty (`desktop-notifications`, on by
default) and iTerm2 (its own sequence; its profiles' notifications on by
default), and rings `BEL` everywhere else, including inside tmux: tmux 3.7c
passes no `OSC 9` on to the terminal it is drawn in, and does pass the bell
(measured). The run-time check is `\.terminalFeatures.postsNotifications`, and
`TUIKIT_NOTIFICATIONS=1`/`0` the user's switch. The message is a localization
key, as a `Text` literal is, with a disfavoured `StringProtocol` twin.

**The fuller version:** inside tmux with `allow-passthrough on` (off by
default), wrap the notification in tmux's DCS passthrough so the client
terminal posts it, where the client is one that would: about two hours, with
a probe of the passthrough. And kitty, recognised by its `TERM`: half an hour.

### B-GHOSTTY-7. The message is made safe, and a leading digit is sent after a space

*V10 (C6): "Text starting with digits and a semicolon would be read as a
ConEmu command … so prefix a space. Sanitise as for titles."*

**Shipped:** the title's sanitiser (control characters dropped, line breaks and
tabs as spaces), and a space before a message whose first character is any
ASCII digit, not only digits followed by a semicolon: the broader test costs a
space in "3 files copied" and cannot miss a spelling some host reads as a
command (ConEmu's `OSC 9` carries `9;1` to `9;12`). A message that is nothing
but spaces after that rings the bell rather than posting an empty
notification. No length cap: none of the hosts documents one.

**The fuller version:** OSC 777 (`notify ; title ; body`), which Ghostty and
kitty also take, for a notification with a title of the app's choosing rather
than the terminal's: about an hour, and a look at each host.

### B-GHOSTTY-8. A request is posted whatever the scene's phase

**Shipped:** the action posts, or rings, whenever it is called. Whether the
person is looking is the app's to judge, with `\.scenePhase` (mode 1004 makes
it `.inactive` while the terminal's window is not focused), as the action's
documentation shows. A request made as the app quits, which no frame would
write, is written in the exit's farewell.

**The alternative:** hold a request back while the scene is active and drop
it, or ring the bell instead. Half an hour; it would take the choice away from an app that wants a
notification anyway (a long job it was asked to report on).
