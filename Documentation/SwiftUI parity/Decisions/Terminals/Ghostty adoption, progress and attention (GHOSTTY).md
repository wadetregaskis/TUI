# Ghostty adoption, progress and attention: decisions for review

*The GHOSTTY lane's companion to
[`SwiftUI API completion decisions.md`](<../SwiftUI API completion decisions.md>),
in its format, for steps V8 and V10 of
[`Ghostty VT reference adoption study.md`](<../../../Terminals/Ghostty VT reference adoption study.md>) §6:
a progress bar the terminal draws (C3, your Q3: yes) and a request for the
person's attention (C6, Q4: yes, after progress), both on the terminal host
ledger lane O9 built for the window title. 2026-10-19.*

- **A. Needs your decision.** None.
- **B. Shipped the safe option.** Eight.
- **C. Declined without asking.** None.

Which terminals take what was read from each one's own documentation on this
machine, since nothing could be fetched: Ghostty 1.3.1's configuration
reference, the help text in iTerm2 3.7.6's binary, tmux 3.7c's manual and
kitty 0.49.1's changelog. tmux's behaviour was measured with the new
`Tools/TerminalProbes/progress_probe.py`; the GUI hosts' are owed to a look.
See `Terminal compatibility survey.md`, "Progress and attention".

## B. Shipped the safe option

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

