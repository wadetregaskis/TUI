# Ghostty adoption, progress and attention: decisions for review

*The GHOSTTY lane's companion to
[`SwiftUI API completion decisions.md`](<SwiftUI API completion decisions.md>),
in its format, for steps V8 and V10 of
[`Ghostty VT reference adoption study.md`](<../../Terminals/Ghostty VT reference adoption study.md>) §6:
a progress bar the terminal draws (C3, your Q3: yes) and a request for the
person's attention (C6, Q4: yes, after progress), both on the terminal host
ledger lane O9 built for the window title. 2026-10-19.*

- **A. Needs your decision.** None.
- **B. Shipped the safe option.** Five.
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
gives iTerm2 and not Ghostty (measured), as it does with hyperlinks.

**The fuller version:** kitty, which draws the bar from 0.47.0, recognised by
its `TERM` and its XTVERSION answer's version, so an old kitty is never sent
one: about an hour, plus a run on a kitty that can open a window (this
machine's cannot).

### B-GHOSTTY-2. The bar is sent again every five seconds, an unmeasured interval

*V8 (C3): Ghostty removes a bar no program has updated for about fifteen
seconds.*

**Shipped:** while a bar is up it is sent again whenever it has gone 5 s
unsent, a third of Ghostty's limit, to every host that is sent one: from a
frame that is drawn anyway, or between frames by the run loop, which wakes for
it and draws nothing (`TerminalHostState.keepAlive(atNanos:)`,
`FramePacer.waitNanos(now:pollingPendingInput:until:)`). That is a dozen bytes
every 5 s on a still screen with a bar up, and one wake of the loop.

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
`showsProgress`; constant for the run, published by the run loop from the
terminal identified at startup and the user's switches; `false` outside a
running app.

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
