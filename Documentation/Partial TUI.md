# Partial TUI: the design

**Status:** a design, for after 1.0 unless the owner says otherwise. Nothing here is built, and no source in
`Sources/` changes with this document. The owner asked on 2026-11-01 about a grid UI at the bottom of the terminal
with normal scrollback above it, called it a tangent, and asked whether it helps accessibility. Written on
2026-11-02 against `main`. The [Future options](<Future options.md#partial-tui>) entry links here.

**How far to trust a statement:**

| Mark | Meaning |
|---|---|
| **[measured]** | A record in `Tools/TerminalProbes/data` or the compatibility survey. Nothing new was measured for this document. |
| **[read]** | Read in TUI's source, or in the SwiftTUI comparison's answers, which carry their own marks. |
| **[inferred]** | My reasoning. Nobody has run it. Almost everything about terminal behaviour on the primary screen is this. |

## The answer, first

1. **Worth having after 1.0, for a kind of app TUI can't serve today:** a deploy tool, a test runner, an installer
   or a REPL, whose output belongs in the user's scrollback and whose controls fit in a dozen rows. It is not a way
   to run the page apps TUI serves now.
2. **The API is one scene modifier and one environment action,** both TUI-specific, with nothing of SwiftUI's
   changed. `WindowGroup { … }.inlineInTerminal()` and `@Environment(\.printAbove)`.
3. **The frame writer barely changes.** It writes absolute positions, and `startRow` is already a parameter
   everywhere that matters, with `1` at every call site. Don't move to cursor-relative positioning. What's new
   is an anchor: the row the frame starts on, learned by a cursor report and kept up to date.
4. **Three things are hard.** Resize, because terminals reflow the primary screen and each in its own way. Pushing
   lines into scrollback without repainting the frame. And one nobody would guess: **the emoji compensations are
   built from alternate-screen measurements, and the two screens differ** (iTerm2 advances a VS-16 emoji by 2 on one
   and 1 on the other) **[measured]**. The writer needs a second model.
5. **Accessibility: it helps a little, and it is not the way to get there.** A full-screen app gains almost nothing.
   An app redesigned to print its results into scrollback gains a lot, but from the printing, not from the grid. The
   cursor hidden off the focused control, the writes that hop around to paint a spinner, and the lack of any names or
   roles are all still there, in fewer rows. If accessibility is the goal, the real cursor and "still" come first, for
   days of work rather than weeks. Section 6.
6. **About 13 commits, two to three weeks of one lane [inferred].** No cost to an app that doesn't ask for it, beyond
   one stored row in place of a constant.

## 1. What it is

An app that draws in `H` rows at the end of the terminal's normal output. No alternate screen. What was on screen
stays above it, and what the app prints goes above it and into scrollback, where the wheel, search and copying are
the terminal's own. On exit the last frame stays where it was and the shell prompt comes up below it.

Prior art, from memory and not re-read for this: `fzf --height`, Bubble Tea without its alternate-screen option, Ink,
ratatui's `Viewport::Inline` with `insert_before`, and Textual's inline mode. Each of them handles resize imperfectly,
which is a fair warning about section 3.5.

## 2. The API

```swift
@main
struct Deploy: App {
    var body: some Scene {
        WindowGroup { DeployPanel() }
            .inlineInTerminal(height: .fit(maximum: 12), onExit: .keepLastFrame)  // both are the defaults
    }
}

struct DeployPanel: View {
    @Environment(\.printAbove) private var printAbove

    var body: some View {
        Button("Deploy") {
            printAbove("Deploying to staging")                       // a plain line
            printAbove { Text("Deployed").bold().foregroundStyle(.green) }   // a view, rendered once
        }
    }
}
```

**Why a scene modifier, and why not `windowStyle`.** SwiftUI's own candidates are `windowStyle(_:)`,
`defaultSize(height:)` and `windowResizability(.contentSize)`, and `.windowStyle(.inline)` reads well. They are
unavailable stubs in TUI, saying that an app fills the terminal window (`Scene+SwiftUIUnavailable.swift`) **[read]**,
which stays true of every other style. No SwiftUI source says `.inline`, so reusing the name buys no compile-as-is.
And a window style is about looks, whereas this changes the app's whole relationship with the terminal.
CLAUDE.md's rule is to keep TUI-specific API separate, and `.mouseSupport(_:)` is the pattern to follow.

**The height.** `.rows(n)` is exact. `.fit(maximum:)` follows the content's natural height up to `maximum`, measured
as `renderOnce` measures it (`ViewRenderer.naturalHeight`) **[read]**. Neither exceeds the screen.

`.fit` has a trap: a `List` or a `ScrollView` has little natural height, and most views offered nothing answer
nothing, so such a page wants `.rows(n)`. The documentation says so. While a modal or a menu is up, `.fit` takes its
`maximum`, as a presentation doesn't add to the page's natural height **[inferred]**.

**`printAbove`** is an environment action, called like `openURL`. The string form writes the text with no padding, so
the terminal wraps it softly, it rewraps on resize and a copy gets the whole line; control characters are dropped.
The view form renders once, at the current width, like `renderOnce`. In a full-screen app the lines are held, and
written after the alternate screen is left at exit, as `SoftTrap` holds its reports **[read]**: the same call means
"this outlives the UI" under either kind of app.

**A plain `print`** writes at the cursor, over the frame, as it does in a full-screen app today. Capturing stdout with
a pipe could send it above, and a child process's output with it, which is half of what a deploy tool does. It is
POSIX-only and needs a thread, so it is a later option and not part of this design.

## 3. The frame writer without the alternate screen

### 3.1 Keep absolute positions, and don't go cursor-relative

`writeDiff` emits a `CUP` before every span and every whole line, and `moveCursor` is the only way it moves; compensation
and placements depend on it (graphics notes §11.2). `startRow` is already threaded through `writeContentDiff`,
`BandTarget`, `plan.sequences(startRow:)`, both `place(on:startRow:)`s and `ReplayableFrame`, and every caller passes
`1` **[read]**. Terminal height is read in one place on the frame path (`RenderLoop.swift:543`) and published from
there as the screen's size **[read]**. So the region is two small changes: the height read gives `H`, and `startRow`
becomes the anchor. `parkCursor` adds the anchor as well.

| | Absolute, with an anchor | Cursor-relative |
|---|---|---|
| The writer, placements, the planner, the replay | unchanged | every `CUP` rewritten, and the last-row and last-column reasoning redone |
| Another process writes to the terminal | draws on the wrong rows until the next re-anchor | draws below that output, intact |
| A resize | needs the anchor re-learned | needs the same, or moves from a position it can't know |
| Needs from the terminal | a cursor report | nothing |

The other-process case is the one real loss, and it damages a full-screen app today as well. A host that doesn't answer
a cursor report gets the alternate screen, so the app still runs **[inferred]**. Every host measured here answers one:
the probes all rely on it **[measured]**.

### 3.2 Reserving the rows

At startup, before the identity and graphics handshakes, so that whatever those print lands in the region and is erased:

1. Flush stdout, as `renderOnce` does. Ask `ESC[6n`, giving row `r` and column `c`. If `c > 1`, line-feed first: the
   program's output didn't end its line.
2. Write `H - 1` line feeds and go back up `H - 1` rows. Near the bottom of the screen that scrolls, and the old rows go
   into scrollback where they belong.
3. The anchor is `min(r, screenHeight - H + 1)`.

A frame that grows at the bottom of the screen does the same for the difference, and lowers the anchor by what scrolled.
**`previousLines` stays valid**, since the frame's rows moved with the screen. A frame that shrinks keeps its anchor, and
`writeDiff` already blanks the rows it no longer has (`previousLines.count > newLines.count`) **[read]**.

### 3.3 Pushing lines into scrollback

Done once a frame, however many lines were printed in it, inside the frame's synchronised hold:

1. Go to the anchor and erase to the end of the screen (`ESC[J`). Nothing below the region is anyone's.
2. Write the lines. The terminal scrolls as it needs to, which is how they reach scrollback, in the normal way.
3. Reserve again as in 3.2, invalidate the writer, and repaint the frame.

That costs one full frame of `H` rows, a few KB, per printing frame, and it needs no host table. On a host with no hold
(Apple Terminal, by the survey's hypothesis) the region can flash **[inferred]**.

**A better way exists, and needs measuring first.** Set a scroll region from row 1 to the row above the anchor, write
the lines at its foot, and release it. The frame isn't touched. It only works once the frame sits at the screen's foot,
and whether rows leaving the top of a region go into scrollback depends on the host: "may push rows to scrollback on some
hosts" is all the [scroll regions study](<Performance/Scroll regions for output.md>) has **[inferred]**, and iTerm2 has a
setting for it. `scroll_region_probe.py` is where to ask. It matters more than the bytes suggest, for section 6's reason.

### 3.4 Exit

`.keepLastFrame` is the default, and `.erase` is the other (`fzf`'s). `Terminal.handBack` is one path, with `quitDebt` as
its bytes for a `SIGQUIT` and a test holding the two to each other **[read]**. Under inline, it:

1. **Renders one last frame** with focus cleared and motion off, so nothing is stuck mid-breath, and with
   `\.terminalGraphics` false. Otherwise the picture's cells would outlive the image the farewell deletes, and history
   would hold placeholder cells that name nothing **[inferred]**. Half blocks survive anything. This is the one place the
   exit does more work than it does today.
2. Writes the farewell, resets styling, turns off raw mode and shows the cursor, as now.
3. **Doesn't** leave the alternate screen. `quitDebt` already checks `isOnAlternateScreen`; `handBack`'s call to
   `exitAlternateScreen()` doesn't **[read]**.
4. Moves to the row below the frame and line-feeds, so the prompt comes up beneath it. For `.erase`: to the anchor, and
   `ESC[J`.

**The signal debt** (`FatalSignalTerminalRestore`) is written ahead of time, so it has to be re-armed whenever the anchor
moves, carrying the position, or a crash leaves the prompt on top of the frame **[inferred]**. `armSignalRestore` is
already the door for that **[read]**.

**Suspending** erases the frame and leaves the cursor at the anchor for the shell. `retakeTerminal` re-reserves from
wherever the cursor is by then, with a full repaint.

### 3.5 Resize, the hard one

On the alternate screen, a resize is cheap: `invalidate()` and repaint. On the primary, the terminal has already reflowed
the frame's rows before the signal reaches TUI, and how varies by host:

- Narrower: a host that rewraps turns frame rows into several. A row TUI wrote with autowrap off (`?7l`) isn't marked as
  wrapped, and whether a host then cuts it or wraps it isn't known **[inferred]**.
- Shorter: the top rows go into scrollback on most hosts, and there the frame's rows are junk history that nobody can
  take back. Every inline tool shows this.
- Taller: some hosts pull rows back from scrollback, moving everything down.

**The one thing a terminal reliably carries through a reflow is the cursor.** So:

- Park the hidden cursor on the frame's first cell, whenever no text control has the focus.
- On a resize, ask `ESC[6n`, and the answer is the new anchor, however the rows reflowed. Erase to the end of the screen
  from there, which takes all of the old frame whatever shape it's now in, then reserve and repaint.
- With a text control focused, the cursor is on its insertion point, for an input method's sake (`RenderLoop+Cursor.swift`)
  **[read]**. There the anchor is that row minus its offset, which is right unless the shrink wrapped rows above it, and
  then a wrapped fragment stays above the frame. It's left there: the alternative is erasing rows that may be the user's.

The answer to the cursor report comes through the input stream, so the frame waits for it, briefly, by the same path as
the startup handshake, and a drag sends many. Coalesce them, as `onInteractiveResizeChange` knows a drag from a stop
**[read]**. All of this is a design until the probe in commit 1 says what each host does.

### 3.6 The rest of what the primary screen changes

| Thing | Why it changes | What to do |
|---|---|---|
| **Advance models** | `Terminal compatibility survey.md`: "advance can differ between buffers". iTerm2 advances VS-16 emoji by 2 on the primary, 1 on the alternate, and a first pass that got this wrong shipped a bad model. iTerm2 is also sensitive to write boundaries on the primary. Every current model and `ChromeGlyphAdvanceTests` read `-alternate.json` records **[measured]** | Re-run `advance_probe.py` without `PROBE_ALT` on each host, and choose the model by screen where the writer freezes it at startup. A whole commit, and the survey grows a column |
| **Scroll output** | The planner's regions could push frame rows into scrollback | Level `.off` under inline, at first. The door exists: `marksOnScreen` already forces it **[read]** |
| **`ESC[2J`** | Would wipe the user's screen | None is written in `TUIApp` **[read]**. The handshakes' `ESC[J` from a saved cursor falls inside the reservation |
| **The root's background** | A painted page in twelve rows looks like a box stuck to the terminal | The root paints no field of its own under inline, unless the app states one **[inferred]** |
| **Hairlines, pictures under text** | Placements scroll with the text, and into history | Off under inline at first: both have glyph forms. Pictures in the frame stay, by §3.4's rule |

## 4. What breaks and what's fine

| Feature | Under inline | Why |
|---|---|---|
| **Mouse: the wheel** | **Breaks, so mouse is off by default** | With tracking on, the wheel goes to the app and the scrollback the mode exists for won't scroll. `?1007` only applies on the alternate screen |
| **Mouse: native selection** | Fine with tracking off, across the frame and history | With tracking on it needs the terminal's bypass key, as in any app |
| **Mouse: when asked for** | Works | `.mouseSupport(.full)` still turns it on. Rows are translated by the anchor at one point, and a report above the frame is dropped, not a click at a negative row. Every feature has a keyboard route already |
| **Keyboard, focus, shortcuts** | Fine | Unaffected by where the frame is |
| **Menus, pickers, tooltips** | Fine, cramped | They composite into the frame and size from the published height, which is now `H`. A long menu scrolls in 12 rows |
| **Sheets, alerts, veil** | Fine, cramped | Page-hosted and composited. Detents are fractions of `H`. A big alert clips, as it does on a small terminal |
| **Full-height pages** | Work, and are the wrong fit | `.frame(maxHeight: .infinity)` fills `H`. `NavigationSplitView` and `TabView` at 12 rows work and look it. `.fit` can't size them, so they want `.rows` |
| **Animation replay** | Fine | `ReplayableFrame` carries `startRow` **[read]** |
| **Pictures in the frame** | Fine | Placeholders and classic placements. On a Kitty host a print moves them with the rows, and the repaint places them again |
| **`H` larger than the screen** | Degrades | The frame is the screen, like a full-screen app, with junk history above from each resize |
| **tmux** | Should work | Its own grid and scrollback; copy mode works, a gain. TMUX-HOLD applies the same **[inferred]** |
| **Windows** | Nothing new to port | CPR and scroll are VT, and no new POSIX is needed. `TUIApp` still has no Windows build |
| **`NoTerminal`, pipes** | Unchanged | `runWithoutTerminal` answers first **[read]** |

## 5. The work, in rough commits

Each lands alone, with its tests. Commits 1 and 2 come first because they can change the design.

1. **`inline_probe.py`:** on Ghostty, iTerm2, Apple Terminal, Warp, GNOME Terminal and tmux: what a resize does to rows
   written with `?7l`, where the cursor lands, and whether rows leaving a scroll region's top go to scrollback. Records
   and a survey section.
2. **Primary-screen advance models:** the records, and the model chosen by screen.
3. **`.inlineInTerminal`:** the scene modifier and its types, stored and not yet acted on, as `_MouseSupportScene` is.
4. **The region:** reservation, the anchor in place of `startRow: 1` at each site, the height read, `parkCursor`, and the
   fallback to the alternate screen when no cursor report comes. `.rows` works from here.
5. **Input:** mouse off by default, and rows translated.
6. **Exit:** `handBack`, the debts, the last frame, `.erase`.
7. **Suspend and resume.**
8. **Resize**, as section 3.5. The commit most likely to take twice as long as expected.
9. **`.fit`:** growing and shrinking.
10. **`printAbove`:** the erase, write, repaint form, batched per frame, and held to exit in a full-screen app.
11. **The scroll-region push,** on the hosts commit 1 clears.
12. **The small ones:** the root's field, hairlines off, scroll output off.
13. **Example, DocC, CHANGELOG,** and a PTY test with a history-keeping pyte screen. `TestApp` can test positions but has
    no scrollback, so the real test is the PTY's.

**Cost when unused:** a stored row where a constant `1` is today, read a few times a frame, and an optional that is `nil`.
The usual A/B should show nothing. No new `RenderContext` field: the height goes through the published geometry.

## 6. Does it help accessibility?

**Directly: a little, and only part of it comes from the grid being smaller.** No screen reader has run any of this, and
nothing here has been tested with one. The reasoning rests on how those tools work and on what their users report, as
collected in [the SwiftTUI comparison's answers](<Historical/SwiftTUI comparison, 2026-11/Answers, features.md>), sections 2
and 25.

### 6.1 What readers actually follow

VoiceOver, Orca and NVDA see a terminal's text and a caret, and read what was just inserted. Speakup and BRLTTY follow the
cursor. So their signals are the caret's position and what just changed, and the worst case is a full-screen frame with a
hidden cursor and hops around to write diffs, which is exactly what TUI emits today.

### 6.2 What it would improve

| What | How much | Why |
|---|---|---|
| **Lines printed above** | **A lot, if the app is built that way** | Text appended at the end of the buffer is the event all of these read best. But this comes from the printing, and needs no grid beneath it |
| **History survives** | Moderate | A reader's review mode can go back over scrollback, and the transcript is still there after exit. An alternate screen has neither **[inferred]** |
| **Less at once** | Small | Twelve rows have fewer diffs than fifty, and fewer side-by-side panes to flatten into one line |
| **The focus stays in one place** | Small | A braille window or magnifier stays near the foot, and doesn't have to hunt across a page |

**A catch in section 3.3.** The simple way of printing erases and repaints the frame, so a reader that speaks inserted text
may read the whole frame again on every printed line, which is the very noise that this is supposed to reduce **[inferred]**.
The scroll-region push doesn't touch the frame. So on hosts that allow it, it is an accessibility requirement, not only a
saving, and it's why commit 11 isn't optional if this is ever sold on accessibility.

### 6.3 What it wouldn't fix

Everything in this list is unchanged in twelve rows:

- **The cursor is hidden, and isn't on the focused control.** It parks on a text field's insertion point and nowhere else,
  hidden (`RenderLoop+Cursor.swift`) **[read]**. A reader can't tell what has focus, or which pane of a split row it is in.
- **Writes hop.** A spinner or a breathing focus ring moves the cursor to write and back, so a reader speaks fragments. Focus
  always breathes, by the owner's rule, and the "still" switch isn't in yet.
- **State is colour.** Selection and focus are shown by colour and reverse video, with no words in the text.
- **Nothing has a name or a role.** TUI has no semantic tree, and `.accessibilityLabel` doesn't compile. A row of cells reads
  as what it draws.
- **Side-by-side content still flattens** on any row that has it.
- **A keystroke still redraws,** and the redraw can be re-read.
- **It's the app author's choice.** A user of a full-screen app gets nothing, and can't choose it (6.4).

### 6.4 What to do instead, if accessibility is the goal

The comparison's stages, in its numbers, which are all estimates. None needs this design:

| Stage | Gain | Work |
|---|---|---|
| A: the real cursor at the caret, and following focus | High: it's the signal every tool watches | 2–4 days |
| B: "still": no motion, spinner labels | High, with A: it stops the fragments | 2–4 days |
| C: a linear mode, changed rows as plain text in scrollback | Medium: crude, and works over ssh for any app | about a week |
| D, E: `accessibility*` modifiers that store, and a command reader | High, and it reverses a parity decision | 4–5 weeks |
| **This design** | **Low on its own; high only for apps built around `printAbove`** | **2–3 weeks** |

**The two overlap in one place.** C needs "no alternate screen" and "write lines to scrollback", and it can reuse
`printAbove`'s writer and the exit path, commits 6 and 10's parts at most. Neither needs the other's anchor, resize or fit. So
A and B are worth doing first in any order, and C shouldn't wait for this.

**On forcing it.** A user's `TUI_INLINE=1` at twelve rows would give them a page in twelve rows. At full height it would run a
page app on the primary screen, keeping history above, for a commit's work, and gain a reader almost nothing, as the frame is
still the frame. So there's no such variable. C is the honest version of that switch.

**The test nobody has done.** VoiceOver is on this Mac. One person listening to a small inline prototype and to Example, with
and without A and B, would replace most of this section's reasoning. Any accessibility claim made for this feature should wait
for that.

## 7. What isn't known

- **Everything in section 3.5,** on every host. It's the point of commit 1.
- **Whether rows leaving a region's top reach scrollback,** per host. Decides commit 11.
- **How far the primary's advance models differ** on hosts other than iTerm2. Old records exist
  (`{Apple-Terminal,iTerm2,Warp,ghostty-1.3.1}-advance.json`), for old versions.
- **Whether a Kitty placement scrolls into history and stays,** host by host. The spec says it moves with the text. iTerm2's
  hairline record suggests some do odd things across screens **[measured, survey Q8]**.
- **What it looks like with a real app.** A prototype of commits 3 and 4 on a small demo, about a day, would show whether this
  feels right before the hard commits are paid for.
