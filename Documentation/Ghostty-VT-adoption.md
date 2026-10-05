# Ghostty's VT reference: what TUIkit should adopt

*Read-only study, 2026-10-04, against `main` at `697d9ef48`. Nothing was built,
run or measured, and every cost is an estimate.*

*Inputs:*
- *Three readers' notes on every page under ghostty.org/docs/vt, read from the
  site's MDX source (ghostty-org/website), plus the Ghostty help and config
  pages those pages link to.*
- *Ghostty's source at `main`, fetched 2026-10-04, for three facts the docs
  leave out: `src/terminal/modes.zig` (the mode table) and
  `src/termio/Thread.zig` (the synchronized-output timeout).*
- *The repo.*

*Line numbers are from that tree, and the lanes still in flight will move some
of them. **Hypothesis** marks reasoning, not observation, and each one names
the probe that would settle it.*

Owner, 2026-10-04: examine the reference "and adopt anything that's applicable
and potentially useful". Coordinate with the SwiftUI-API work; serialising
with it is fine.

---

## 0. In one page

**What the reference is.** About 75 pages:
- five C0 controls, eight ESC sequences and 29 CSI sequences;
- 24 OSC pages;
- two external protocols, OSC 8 links and kitty's OSC 21 colour stack.

Ghostty calls it a work in progress and implements more than it lists: mode
2048 is in its source and nowhere in its docs.

Most of the reference describes cursor, erase and margin semantics. The
readers checked TUIkit's code against them and found **no bug** in the cursor
model, the right-edge compensation, the sanitiser, the reply parsers or the
terminators. Ghostty's CUF page ("never wraps") confirms the compensation's
right-edge reasoning. What is worth taking is below.

**Ranked by value for the cost.**

| # | Item | Group | Value | Cost | Waits on | Owner? |
|---|---|---|---|---|---|---|
| 1 | Synchronized output (mode 2026) around multi-row frames | OUTPUT | high | ½ d | keyboard lane | no |
| 2 | OSC 52 clipboard writes: Ghostty's four rules folded into the clipboard step | CAPABILITY | high | 0 extra (the lane owns ~1½ d) | the decisions-text lane | decided |
| 3 | Truecolour when `TERM` names Ghostty or kitty and `COLORTERM` was not forwarded. **Today, by reading the code: 16 colours over ssh** | DETECTION | medium | 3 h | nothing | no |
| 4 | Application-mode cursor and keypad keys (SS3), plus asserting the inherited defaults at startup | CORRECTNESS | medium | ½ d | keyboard lane | no |
| 5 | Window title (OSC 2), on a shared host-state ledger | CAPABILITY | medium | 1 d | A28 lane | decided (A28 §9, P15) |
| 6 | Progress bar (OSC 9;4) | CAPABILITY | medium | 1½ d | A28 lane | Q3 |
| 7 | Shift-click reaching the app on Ghostty (XTSHIFTESCAPE) | CAPABILITY | medium | 1 d | A13 lane | Q1 |
| 8 | Pointer shapes (OSC 22), O12 option (b) | CAPABILITY | medium | 2½ d | A13 and A28 lanes | Q2 |
| 9 | Hardware scrolling of full-width bands (DECSTBM + SU/SD) | OUTPUT | medium (hypothesis) | ½ d estimate, then 3–5 d | A28 lane | Q5 |
| 10 | DSR 5 as the only startup fence (CPR collides with modified F3) | CORRECTNESS | low | 2 h | nothing | no |
| 11 | OSC 8: name the host in `file://` links; skip links over 2083 bytes | CORRECTNESS | low | 3 h | nothing | no |
| 12 | DECSC/DECRC in the frame dump and the graphics probe | CORRECTNESS | low | ½ h | keyboard lane (dump); nothing (probe) | no |
| 13 | Autowrap off while the app owns the screen | CORRECTNESS | low | ½ d + cards | keyboard lane | no |
| 14 | Byte trims: no padding after `EL`, `ECH` for blank runs, `CUF` between spans, the default `CUP` column | OUTPUT | low | ½ d measure + 1 d | A28 lane | no |
| 15 | Attention: desktop notification (OSC 9) or BEL | CAPABILITY | low | 1 d | A28 lane | Q4 |
| 16 | XTGETTCAP `RGB` for terminals identified but not named by `TERM` | DETECTION | low | 2 h probe, then 1 d | item 10 | no |
| — | Compatibility-doc facts from Ghostty's pages and source | DETECTION | — | 2 h | lands with each step | no |

About 16 working days in all, 4½ of them the hardware scroll. The clipboard
cost is the decisions-text lane's, not this track's.

**Do these three first.**
1. **Synchronized output.** Ghostty's own help page names the defect: apps
   that redraw large areas tear or flicker on it, especially when they erase a
   row and then redraw it. TUIkit's whole-line path does exactly that
   (`ESC[2K` + content, FrameDiffWriter.swift:529-531). The fix costs 16 bytes
   on a multi-row frame, and terminals without the mode ignore it.
2. **OSC 52.** Already queued, by the owner's clipboard rule. Ghostty's page
   adds four rules the writer must follow (§1.2 C1). One matters more than the
   rest: an invalid payload *clears* the user's clipboard.
3. **Truecolour over ssh.** `ColorDepth.detect` falls to `.basic16` for
   `TERM=xterm-ghostty` or `xterm-kitty` when `COLORTERM` is missing. That is
   OpenSSH's default, since it forwards `TERM` but not `COLORTERM`. Three
   hours of work.

**What waits.** Most of the rest touches files that SwiftUI lanes own:
- the keyboard lane, in flight: `Terminal.swift`, `KeyEvent.swift`,
  `App.swift` and the new `FatalSignalTerminalRestore.swift`;
- the decisions-text lane, queued: clipboard, A13 selection,
  `MouseEventDispatcher`;
- A28 chrome, decided but not launched: `RenderLoop.swift` and
  `FrameDiffWriter.swift`'s regions.

§6 orders the work. Four small steps can run now in a lane of their own, and
everything else follows the lane that owns its files.

**What it does not change.**
- **A5.** In-band resize reports (mode 2048, in Ghostty's source but not its
  docs) carry a size and never a drag's start or end, so the quiet-period
  inference stays.
- **B53.** No terminal sequence reports Reduce Motion, so the owner's
  environment-variable-plus-setting decision stands.
- **A16.** Ghostty's colour model is SDR, so "HDR supported" stays false on
  every host, honestly.
- **OSC 8.** Already shipped; two small fixes (item 11).

**Seven owner questions** (§5): Shift-click capture, pointer shapes (O12), a
progress API, an attention API, the hardware-scroll budget, whether TUIkit may
ever set the terminal's own colours, and the landing order.

---

## 1. Adopt

Each entry covers the mechanism, the API, how it degrades, detection, cost
and how it is measured. The hosts are those in `Terminal-compatibility.md`:
- Apple Terminal 455.1
- iTerm2 3.6.11
- Ghostty 1.3.1
- Warp v0.2026.09.02
- tmux 3.7c

kitty is installed on this VM but is not a modelled `TerminalClient.Program`,
so it is recorded as an observation only.

### 1.1 OUTPUT

How output items are measured:
- **Bytes** are deterministic, so an agent may capture them: `drive.py --dump`
  on a scenario, then `analyze_stream.py`.
- **CPU** on the emission path is `emit_bench.py OLD NEW --scenarios … --host
  …`. The owner runs it on a quiet box; agents never benchmark.
- `ab_bench.py` drives `Stress --bench`, which never runs `FrameDiffWriter`
  (emit_bench.py's docstring proves this). It cannot see any item in this
  group, so it is not used here.
- Every item here changes drawing, so `Stress --selfcheck` is a gate.

#### O1. Synchronized output (DEC mode 2026) — adopt

- **Mechanism.** `CSI ? 2026 h` (begin) and `CSI ? 2026 l` (end) bracket the
  frame. The terminal holds its display until the end marker, so a repaint
  that arrives in several reads is shown whole. Three placement rules:
  - **After the image transmissions, before the first cell.** `writeFrame`
    writes pending graphics first, inside `beginFrame`
    (RenderLoop.swift:1084-1092). Transmissions draw nothing. Keeping
    megabytes of them outside the hold keeps Ghostty's timeout from expiring
    mid-hold.
  - **Only frames that write more than one row.** A breath frame of one or
    two cells cannot tear and would pay 16 bytes, a large share of its size.
    `FrameDiffWriter` knows how many rows it wrote. `beginFrame` reserves 8
    bytes at the buffer head, and the flush starts at offset 0 or 8, so there
    is no copy.
  - **Teardown.** Send the end marker in `disableRawMode`, after a failed
    `writeAll` (Terminal.swift:804-815, which gives up on a hard error), and
    in the fatal-signal debt the keyboard lane adds
    (`FatalSignalTerminalRestore.swift`).
- **Crash with the hold open.** Ghostty resets the mode after 1000 ms
  (`sync_reset_ms`, src/termio/Thread.zig). A process killed mid-frame
  freezes Ghostty's display for one second at most. Other hosts' timeouts are
  unmeasured.
- **Ghostty's other advice** on the same page is to update cells in place and
  erase the tail with EL rather than erasing first. That is O3's padding
  trim.
- **API.** None: it is not a SwiftUI concept, and nothing an app chooses.
  `TUIKIT_SYNCHRONIZED_OUTPUT=0` is the user's off switch, in the shape of
  the keyboard lane's `TUIKIT_KEYBOARD_PROTOCOL=0`.
- **Degrades.** A host without the mode ignores it.
  - The shape (`?`, no intermediate) was measured clean on Terminal.app,
    iTerm2, Ghostty and Warp (Terminal-compatibility.md:550-566).
  - `?2031h`, the same shape, printed nothing on five hosts (:2355-2361).
  - It is sent blind. Its DECRQM query is the one shape Apple Terminal
    prints, and emitting the mode does not need the query.
- **Detection.** None at run time. For the compatibility doc's table, ask
  DECRQM `?2026$p` on identified non-Apple hosts only, gated as 2027 is.
  - Ghostty: documented (help page) and in its source
    (`synchronized_output = 2026`).
  - iTerm2, kitty, Warp, tmux: **hypothesis**.
  - Whether tmux carries a pane's hold to the client is unmeasured.
- **Cost.** About ½ day.
- **Measure.**
  - Bytes on `tour` and `splitdrag`: expect +16 per multi-row frame and
    nothing on breath frames.
  - CPU: `emit_bench.py --scenarios animating scrollfollow kitchensink`,
    `--host ghostty` and `--host Apple_Terminal`. Expect no measurable
    difference.
  - Probe: a new `Tools/TerminalProbes/sync_probe.py`. It checks the CPR
    column before and after the pair on Apple Terminal (the leak method of
    :547-560), runs the DECRQM survey on identified hosts, and records tmux.
  - Visual: a human watches `drive.py --scenario splitdrag` on Ghostty, before
    and after.

#### O2. Hardware scrolling of full-width bands (DECSTBM + SU/SD) — adopt if the estimate pays

- **Mechanism.** In `writeDiff`, before the row loop:
  1. Find a shift *k* (|k| ≤ height/2) and the longest contiguous band
     [a, b] where `newLines[i] == previousLines[i+k]`. This is string
     equality on rows already built.
  2. If the band pays (say at least 4 rows, and more bytes saved than about
     20 spent), emit `CSI a;b r`, then `CSI k S` (or `CSI k T`), then
     `CSI r`. All three go in the same frame, inside O1's hold, so the region
     never outlives the frame.
  3. Rotate `previousLines` and the `CellCache` by *k*.
  4. The ordinary diff then writes the exposed rows and any residue: the
     indicator thumb, the selection.

  IL and DL are not needed: deleting a row is SU in a band that starts at it.
  Ghostty's SD page shows SD acting on the region wherever the cursor is,
  which is why SU/SD beat IL/DL and IND/RI here. Neither depends on the
  cursor.
- **Full width only.** A sidebar beside a scrolled list breaks row equality.
  Left and right margins (DECSLRM) would fix that, but Apple Terminal and tmux
  lack them: out of scope.
- **Exclusions until the cards say otherwise.**
  - Rows with Apple-Terminal-compensated clusters: nothing is known about how
    a scroll moves stored versus painted width (compat :640-646).
  - Rows carrying iTerm2 inline images.
  - Animation-replay rows.
- **Order.** After A28. Today `FrameDiffWriter` diffs three regions
  (`OutputRegion`, FrameDiffWriter.swift:146-150). A28 makes chrome views of
  one host, so a band is found in one buffer. K2's startup `CSI r` /
  `CSI ? 6 l` must land first: this item sets a region, so it must not
  inherit one.
- **API.** None.
- **Degrades.**
  - DECSTBM, SU and SD are VT100/VT220-era, and their shapes have no `?` and
    no intermediate, so Apple Terminal consumes them.
  - SU and SD are unmeasured on Apple Terminal and Warp. If a card shows a
    host without `CSI n S`, fall back to *k* × IND at the bottom margin
    (VT100), or gate per `Program`.
- **Detection.** None if the cards pass.
- **Cost.** ½ day for the estimate (M0), then 3–5 days.
- **Measure.**
  - **Estimate first.** Extend `drive.py --dump` to mark step boundaries
    (after O1 lands, the hold markers already delimit frames). Add a
    `--shift` mode to `analyze_stream.py` that replays the stream through a
    screen model (pyte, as `Tools/Smoke` uses) and counts, per frame, the
    bytes a band shift would have saved.
  - **Bytes.** `drive.py --scenario scroll` and `list`, before and after.
    The documented baseline for `scroll` is 45,264 bytes
    (`Intra-line output diffing.md`:326). **Hypothesis:** 80–95% fewer bytes
    per step for text-heavy lists.
  - **CPU.** `emit_bench.py --scenarios scrollfollow scrolleager megalist`.
    The detection costs a compare per row per frame, so `kitchensink` and
    `animating` (no scrolling) must show no difference.
  - **Cards.** A scrolled band holding emoji, an image and a right-edge glyph,
    on Apple Terminal (light and dark), iTerm2, Ghostty, Warp, kitty and
    tmux, in the style of `treatment_card.py`.

#### O3. Byte trims — one capture decides all four

| Trim | Today | Change | Expected (hypothesis) |
|---|---|---|---|
| Padding after `EL` | A whole-line row appends `terminalWidth - clippedWidth` spaces after a head `ESC[2K` that already painted those cells in the row background (FrameDiffWriter.swift:529-531). This is BCE, which TUIkit relies on everywhere. | Drop them from the bytes. Keep them in the cell model: the decomposer fills blanks after a head `K` (String+CellSpanDiff.swift:110-113, 265-271). | Single digits to ~10% of a full repaint; nothing on span frames |
| `ECH` for blank runs | A span ending in a run of background-only blanks writes them as spaces | `CSI n X` for n ≥ ~5 at a span's end. ECH leaves the cursor in place, so mid-span it is not worth it. | Low single-digit % on gestures (splitdrag: cells 18.8% of bytes, SGR 69%) |
| `CUF` between spans | Every span gets an absolute `CSI r;c H` (FrameDiffWriter.swift:891-893) | `CSI n C` for the second and later spans on a row. The span path runs only on rows of single-cell scalars (String+CellSpanDiff.swift:205-216), so the column is known. Re-tune `spanMergeGap` (:948). Use CUF, not HPR: HPR is unmeasured on Apple Terminal and Warp and adds nothing. | 2–6% of span-heavy frames (splitdrag ≈ 2.6 KB/frame) |
| Default `CUP` column | `CSI row;1 H` for every whole-line row (ANSIRenderer.swift:408-410) | `CSI row H`, and `CSI H` for 1;1 | Under 1% |

- **API.** None.
- **Degrades.** Nothing new. `ESC[2K` BCE, `ECH` and `CUF` already reach
  every measured host through the existing erases and compensation walks.
- **Card.** Apple Terminal's light profile, because of the background-leak
  history at FrameDiffWriter.swift:520-526.
- **Cost.** ½ day of measurement, shared with O2's M0, then about a day: one
  commit per trim, each kept only if its capture shows ≥ 3% on its scenario.
- **Measure.**
  - Bytes: `drive.py --dump` on `tour`, `splitdrag`, `table` and `scroll`,
    then `analyze_stream.py`.
  - CPU: `emit_bench.py --scenarios textwall kitchensink table`.
  - Count the byte-exact goldens each trim moves before committing to it.
- **Order.** After A28, which reshapes `FrameDiffWriter`'s regions; or before
  it starts. Never alongside.

### 1.2 CAPABILITY

**One mechanism for state outside the grid.** A title, a progress bar and a
pointer shape each need the same four things:
- the value the app wants this frame (a preference, or the dispatcher's
  answer);
- the value last sent;
- a write on change, inside the frame;
- a reset on suspend, exit and fatal signal, re-sent on resume.

`Terminal.applyMouseSupport` (Terminal.swift:497-521) is that pattern for one
value. Build it once, as a `TerminalHostState` owned by the render loop (an
instance, not a static), with one entry per value. Do not build four copies.
The fatal-signal debt gains each entry's reset bytes.

**Run-time capability, per the A18 rule.** Each API compiles everywhere and
has a documented run-time check:
- a per-`Program` table on `TerminalClient`, in the shape of
  `honoursHyperlinks(_:)` (TerminalHyperlinkSupport.swift:77-82);
- an app override and a `TUIKIT_*` environment switch;
- surfaced to views as **one** environment value, shaped like the keyboard
  lane's `\.keyboardReporting` (KeyboardReportingEnvironment.swift in that
  lane).

Whichever lane lands first creates the value, and the others add fields. The
clipboard lane's "is there a route" answer belongs there too.

#### C1. OSC 52 clipboard writes — adopt, in the decisions-text lane (no separate work)

The owner's rule (10-04): never touch the server's clipboard unless confident
the client is on this machine; OSC 52 wherever available; with no route, say
so. The lane (`plan/wave_d4x.js`, C0 probe then C1 writer) already carries
that rule. Ghostty's page (and its config reference) adds:

1. **Spell `c` explicitly:** `ESC ] 52 ; c ; <base64> ESC \`. An empty
   selector means `c` on Ghostty but `s0` on xterm.
2. **Never send an empty or invalid payload.** Quoted: "If `d` is neither a
   valid Base64-encoded string or the character `?`, all clipboards listed in
   `t` are cleared." Skip empty copies, use unwrapped base64 (Foundation's
   default), and test the encoder against exactly this failure.
3. **One selector per sequence.** Ghostty accepts no more than one.
4. **Write only.** A `?` read prompts by default (`clipboard-read = ask`), and
   its reply arrives asynchronously in the input stream. Paste stays the
   terminal's own, through the bracketed paste already on.
5. **No documented size ceiling.** The lane's `clipboard_probe.py` ceiling
   test covers Ghostty.
6. **DA1 can only add support.** iTerm2's DA1 carries `52` (compat :3090).
   Ghostty's `ESC[?62;22c` does not, although Ghostty writes by default
   (`clipboard-write = allow`). The per-`Program` table is therefore the main
   rung of the ladder, not DA1.
7. **Locality.** The text-editing study's §4.4 ("both, when both apply",
   using only the `SSH_*` variables) predates the owner's rule. Under the rule,
   the local helper runs only on positive evidence: no `SSH_*`, no mosh, and,
   under tmux, a client whose parent chain does not reach `sshd` or
   `mosh-server`. TerminalHost already walks that chain for emoji (compat
   :1655-1670). Do not build the study's §4.4 as written.

- **Degrades.** Every measured host swallows the OSC (compat :2845-2856). A
  host that does not honour it loses the copy, and the status line says
  "Sent to the terminal's clipboard", not "Copied".
- **Measure.** The lane's `clipboard_probe.py` on Ghostty, iTerm2 (its setting
  on and off), Apple Terminal, Warp and kitty, and tmux with `set-clipboard on`
  and `external`.

#### C2. Window title (OSC 2) — adopt; build once, on the ledger

- **Mechanism.** `ESC ] 2 ; <title> ESC \`, written on change.
  - **UTF-8.** Ghostty "always unconditionally expects" UTF-8. Do not send
    XTSMTITLE: Ghostty ignores it, and the compatibility doc warns that Apple
    Terminal does not parse every CSI generically.
  - **Its own sanitiser.** `sanitizedForTerminal` deliberately keeps C0
    (String+TerminalSanitizing.swift:41-46). A BEL or ESC in a title would end
    the OSC early, and the rest would print or execute. Drop C0, DEL and C1,
    and map newlines to spaces.
  - **Save and restore.** Save with `CSI 22 ; 2 t` on the first set, and
    restore with `CSI 23 ; 2 t` on suspend and exit. Ghostty's reference does
    not list XTWINOPS, so whether any measured host honours the stack is a
    probe question. Where none does, the title stays until the shell's next
    prompt rewrites it, which both Ghostty's and iTerm2's shell integration
    do.
  - **OSC 2, not OSC 0.** On Ghostty they are the same. Switch to OSC 0 only
    if the probe shows a host whose tab label follows the icon name.
- **API.** SwiftUI's title-taking `WindowGroup` initializers (refusal review
  P15), and A28 §9's decided rule: a root `.navigationTitle` sets the window
  title when no top bar shows it. Nothing new.
- **Degrades.**
  - Swallowed everywhere.
  - Under tmux it sets the pane title. The outer window changes only with
    `set-titles on`, which is off by default.
  - Ghostty with a configured `title` ignores it by design.
- **Detection.** None needed: the write is harmless everywhere.
- **Cost.** ½ day, plus ½ day for `Tools/TerminalProbes/title_probe.py`. The
  probe sets a title, reads it back with `CSI 21 t` where answered (Ghostty
  answers only with `title-report` set), and otherwise screenshots the tab and
  window. It also tries push and pop per host.
- **Ownership.** Build it **once**. Recommended: this track builds the ledger
  and OSC 2 right after A28 lands, and closes P15's title bullet. The A28 lane
  routes the root `.navigationTitle` into the ledger and writes no OSC itself.

#### C3. Progress (OSC 9;4) — adopt if the owner wants the API (Q3)

- **Mechanism.** `ESC ] 9 ; 4 ; s ; v ESC \`.
  - `s`: 0 none, 1 value, 2 error, 3 indeterminate, 4 paused.
  - `v`: 0–100, clamped and rounded.
  - Written on change.
- **Keep-alive.** Ghostty resets the bar after about 15 s and recommends an
  update at least once a second. Re-send every 5 s from a timed wake that
  **does not render**. **Hypothesis:** 5 s is enough, measured by the probe.
  The idle-storm history makes this the risky part, so `idle_cpu.py` with a
  bar shown is a gate: zero renders at idle.
- **Teardown.** Send `9;4;0` on suspend, exit and fatal signal, and re-send
  the bar on resume. iTerm2 may have no timeout at all, so a skipped teardown
  could leave a stale bar after the app quits.
- **API.** TUI-specific, kept apart from SwiftUI names; SwiftUI has no
  equivalent. `.terminalProgress(_ progress: TerminalProgress?)`, where
  `TerminalProgress` is `.value(Double)`, `.indeterminate`,
  `.error(Double?)` or `.paused(Double?)`, and `nil` means no bar. It is
  resolved like a preference, so the last writer wins. Run-time check:
  `honoursProgressReports` in the capability value.
- **Degrades.**
  - Inert on Apple Terminal and Warp (swallowed).
  - Ghostty draws a bar on top of each split.
  - iTerm2 3.6 probably honours it: tmux lists `progressbar` among its client
    features (compat :1638). To measure.
  - **Hypothesis:** tmux forwards it only to clients whose features include
    `progressbar`.
- **Cost.** About a day, plus ½ day for `progress_probe.py`: set 50%, wait
  20 s without a re-send, then set 0, screenshotting each.

#### C4. Pointer shapes (OSC 22) — adopt as O12 option (b), with per-host names (Q2)

- **Mechanism.** `ESC ] 22 ; <name> ESC \`, written when the shape under the
  pointer changes.
  - **Names differ per host.** Ghostty (from 1.0.0), kitty and foot use CSS
    keywords. iTerm2 (from 3.5.0) uses its own X11 subset, to be measured name
    by name. xterm uses X11. Other hosts get nothing.
  - **Ghostty's page warns:** avoid the sequence "unless your program only
    targets certain terminal emulators, or you can switch between cursor names
    by detecting the current terminal". TUIkit does detect the terminal.
  - **Region resolution.** The dispatcher already tracks the pointer for
    `onHover` and `onContinuousHover` (OnHoverModifier.swift:207-266), and
    raises the mouse mode per frame through `requestFeature`.
    `.pointerStyle` records a region the same way. The frame resolves the
    topmost style under the last motion and writes it through the ledger.
  - **Motion reporting (1003)** is requested only while some `.pointerStyle`
    is on screen.
  - **Reset on exit and suspend.** Probe which of `default`, an empty name, or
    leaving the alternate screen restores Ghostty's shell-time pointer.
  - **Built-in shapes, no app code:** `text` over TextField and TextEditor,
    `pointer` over Link and Button, `col-resize` and `row-resize` over split
    dividers and resizable table columns. On only where the reset is measured
    clean.
- **API.** SwiftUI's `pointerStyle(_:)` and `PointerStyle` (macOS 15).
  - Remove the parity-map refusal (parity-map.json:299-305). Its reason, "No
    terminal protocol lets an app ask for a resize cursor", is false.
  - `pointerVisibility(_:)` stays refused unless the probe shows CSS `none`
    hides the pointer on Ghostty.
  - `.image(_:hotSpot:)` stays refused.
  - Run-time check: `honoursPointerShapes`.
- **Correct O12's facts now** (refusal review :971-1000). This is the
  coordinator's job, when the owner reaches O12, because the owner is reading
  that document:
  - iTerm2 supports OSC 22 from 3.5.0, with X11 names, so a CSS-only table is
    wrong for it;
  - xterm uses X11 names;
  - Ghostty's support is documented, not "believed".
- **Degrades.** Swallowed everywhere. The cost of being wrong is a pointer
  stuck in a shape, hence the reset probe. Detection is by identity only: no
  portable query exists, and kitty's `?` query is not documented for Ghostty.
- **Cost.** 2 days, plus ½ day for `pointer_probe.py`. It needs screenshots,
  because the shape is not in the byte stream. Run on Ghostty, iTerm2 and
  kitty. **Hypothesis:** tmux drops OSC 22; to measure.

#### C5. XTSHIFTESCAPE (`CSI > Ps s`) — adopt after the owner picks the policy (Q1)

- **Mechanism.** `CSI > 1 s` asks the terminal to report Shift in mouse events
  instead of keeping Shift-drag for its own selection. `CSI > 0 s` hands Shift
  back.
  - Ghostty honours the request under its default
    `mouse-shift-capture = false`. Its `never` and `always` settings override
    the app.
  - iTerm2, Apple Terminal and Warp document nothing and are expected to
    ignore it.
- **Why.** Today Shift-click range selection (List, TextField, TextEditor) is
  unreachable on Ghostty and Warp, where Shift-click selects text (compat
  :2897-2902).
- **Policy (Q1).** Send `> 1` only while a Shift-click consumer has focus, and
  `> 0` otherwise and at every teardown. Make it app-wide once A13's D1 drag
  selection gives users TUIkit's own selection.
- **API.** Nothing public: an internal flag on `MouseSupport`, set by the
  consumers and applied in `applyMouseSupport`. This is mouse-mode state, so
  it does not need the ledger. User switch: `TUIKIT_SHIFT_CLICKS=0`.
- **Degrades.** Ignored where unsupported.
  - The `>`-marker family (`CSI > 1;2 m`) already goes to every host
    (Terminal.swift:436).
  - `CSI > … s` itself is unmeasured on Apple Terminal. If Apple Terminal
    ignored the `>`, it would act as SCOSC (save cursor), which is harmless.
- **Cost.** About a day. Measure with `mouse_probe.py`, Shift-clicking with
  and without the sequence on Ghostty, Warp, iTerm2, Apple Terminal and kitty,
  plus the CPR leak check on Apple Terminal.

#### C6. Attention: OSC 9 notification, else BEL — adopt at low priority (Q4)

- **Mechanism.** `ESC ] 9 ; <text> ESC \` posts a desktop notification on
  iTerm2, where it originated, and on Ghostty.
  - **ConEmu collision.** Text starting with digits and a semicolon would be
    read as a ConEmu command (`4;50` is a progress update), so prefix a space.
  - **Sanitise** as for titles.
  - **Fall back to BEL** (0x07) where OSC 9 is not honoured. It is written
    outside any string sequence. Content cannot ring it today, because BEL
    becomes a space at the write boundary.
- **Typical use.** A job finished while `scenePhase == .inactive`. Mode 1004
  already drives that phase (Terminal.swift:398-406).
- **API.** TUI-specific: `@Environment(\.requestAttention)`, an action in the
  `OpenURLAction` shape, `requestAttention("Build finished")`. No singleton.
  Run-time check: `honoursNotifications`.
- **Degrades.** Swallowed where unsupported. BEL beeps or flashes according to
  each host's preferences. Delivery can never be confirmed, and the doc says
  so.
- **Cost.** About a day, including a probe on the four hosts and tmux.

### 1.3 CORRECTNESS

#### K1. Application-mode cursor and keypad keys

- **The problem.** DECCKM (`?1h`) and DECKPAM (`ESC =`) outlive the program
  that set them. A killed vim, less or htop, or a shell setup that sends
  terminfo `smkx` without `rmkx`, can leave them on. Keys then arrive in their
  SS3 spellings:
  - arrows as `ESC O A..D`;
  - Home and End as `ESC O H/F`;
  - the keypad as `ESC O M`, `ESC O j..y` and `ESC O X`.

  `parseSS3Sequence` (KeyEvent.swift:266-274) maps only P, Q, R and S and
  drops the rest. A TUIkit app launched after such a program therefore has
  **dead arrow keys**. The compatibility doc's numeric-pad paragraph
  (:3775-3790) assumes nothing else left the mode on.
- **Fix.**
  - Accept every SS3 spelling: arrows, Home/End, keypad Enter, the operators
    `* + , - . /`, the digits and `=`.
  - Keypad digits carry `.numericPad`, the modifier the keyboard lane adds.
  - Under the kitty protocol these keys arrive as `CSI … u`, so this is the
    legacy path: Apple Terminal, unidentified hosts, and
    `TUIKIT_KEYBOARD_PROTOCOL=0`.
- **Cost.** 2–3 hours.
- **Tests.** A `KeyEvent` table, and `InputSplitInvarianceTests` over every
  SS3 spelling split at every byte.
- **Probe.** A PTY smoke that sends `ESC O A` and checks focus moves. On each
  host, run `printf '\e[?1h\e='`, then launch Example.

#### K2. Assert the inherited defaults at startup

Next to `?1049h`, emit:
- `CSI r`: margins to the full screen;
- `CSI ? 6 l`: origin mode off;
- `CSI ? 1 l`: DECCKM off;
- `ESC >`: numeric keypad.

Every CUP assumes there is no region and no origin mode, so a stale region
from a crashed program offsets or clamps the whole frame. These are the
defaults a shell expects, so none is restored on exit.
- **Shapes.** `CSI r` has neither `?` nor an intermediate; `?6l` and `?1l`
  have a `?` and no intermediate; `ESC >` is a two-byte escape. Apple Terminal
  consumes all four.
- **Order.** Must land before O2.
- **Cost.** 1 hour.
- **Tests.** Pin `enableRawMode`'s bytes.
- **Probe.** On each host, run `printf '\e[5;10r\e[?6h'` before launching
  Example. The frame must start at row 1.

#### K3. Autowrap off while the app owns the screen

- **Mechanism.** `CSI ? 7 l` with `?1049h` and on resume; `CSI ? 7 h` before
  leaving, on suspend, exit and the fatal-signal debt.
- **What it buys.** Suppose a host advances a row further than TUIkit claimed:
  an unmeasured host, or iTerm2 and Terminal.app with "ambiguous characters
  are wide".
  - With autowrap off, that row loses its own tail.
  - Today it wraps into the next row instead, and on the bottom row it scrolls
    the whole alternate screen up one line. The diff writer's model is then
    wrong until something invalidates.
- **Cost per frame.** Nothing.
- **Apple Terminal first.** The repaint of its phantom right-edge cell
  (FrameDiffWriter.swift:968-1039) is described as the row *wrapping*. With
  autowrap off it may simply stop wrapping, or the repaint may need adjusting.
  A card session decides.
- **Same commit.** Give the custom-quirks path
  (`TerminalClient.simulatedQuirks` with an over-advancer) the Apple peak
  guard (String+ANSISplitting.swift:428-520).
- **Cost.** ½ day, plus cards.
- **Measure.** An over-wide last-row card on Apple Terminal, iTerm2 (with
  ambiguous-wide on), Ghostty, Warp, kitty and tmux; and `Stress --selfcheck`.

#### K4. DSR 5 as the only startup fence

- **The collision.** Three exchanges end on a cursor-position report:
  identity (TerminalIdentityQuery.swift:80), mode (TerminalModeQuery.swift:73)
  and graphics (TerminalGraphicsQuery.swift:102). A CPR reply is
  `CSI y;x R`, and xterm's modified F3 is `CSI 1;m R`, the same shape. A
  Shift-F3 or Ctrl-F3 pressed during the ≤0.5 s exchange therefore ends the
  identity read early: the terminal is left unidentified, gets no
  compensation, and the key is lost.
- **Fix.** Fence on `CSI 5 n` (answer `CSI 0 n`), which collides with no key.
  - The colour exchange already uses it (TerminalColorQuery.swift:120-138).
  - Every host answered it (compat :2137-2139).
  - The kitty protocol spells F3 `CSI 13 ~` precisely because of this
    collision, but these exchanges run before it is negotiated.
- **Also unblocks** modified F1–F4 (`CSI 1;m P..S`), which
  `parseCSISequence` drops today, without a late CPR being read as Shift-F3.
- **Cost.** 2 hours.
- **Tests.** Each parser ends on `CSI 0 n` and passes over an interleaved
  `CSI 1;2 R`. `identity_smoke.py` gets an injected key.
- **Probe.** Re-run `identity_probe.py` on the four hosts, tmux and screen to
  confirm the replies arrive in order.

#### K5. OSC 8: host-named file links, and a length cap

1. **File links.** `URL(fileURLWithPath:).absoluteString` is `file:///path`,
   with an empty host, and Ghostty documents that it refuses such links. So a
   Link to a local file does nothing on the host that otherwise handles OSC 8
   best.
   - Rewrite a host-less `file:` URI to `file://<hostname>/path`, as the gist
     asks of utilities. Over ssh this names the remote host, which correctly
     stops the terminal opening a same-named local file.
   - Leave `localhost` and explicit hosts alone.
   - Take the hostname from `gethostname()` once, in the TUIkit module.
     TUIkitCore, where `TerminalHyperlink` lives, must keep building on
     Windows, so it is handed the name and never calls POSIX itself.
     **Hypothesis:** `ProcessInfo.hostName` can block on DNS on macOS, which
     is why it is not used.
2. **Length cap.** Skip the OSC 8 wrapping when the encoded URI exceeds 2083
   bytes. VTE and iTerm2 drop such links, and Ghostty 1.1.1 fixed a crash on
   very large ones. The label still draws, and the app-side open still works.

- **Cost.** 3 hours.
- **Tests.** `TerminalHyperlink` openings for file URLs, `localhost`, explicit
  hosts and the cap.
- **Probe.** `hyperlink_probe.py`'s card gains `file://` rows, run on Ghostty,
  iTerm2 and kitty.

#### K6. DECSC/DECRC instead of SCOSC/SCORC

- **The problem.** `dumpLastFrame` (Terminal.swift:576-590) brackets its
  overlay with `CSI s` and `CSI u`. Ghostty's reference lists `CSI s` as
  DECSLRM whenever mode 69 is on, and whether SCORC restores SGR is
  implementation-defined. Afterwards the writer's carried style
  (FrameDiffWriter.swift:243, 877-878) can disagree with the terminal.
- **Fix.**
  - Use `ESC 7` and `ESC 8`, which save and restore SGR as well.
  - Call `forgetTerminalStyling()` after the dump.
  - Make the same swap in the graphics probe (TerminalGraphicsQuery.swift:96,
    101). There it is cosmetic: no measured host leaves mode 69 on.
- **Cost.** Half an hour. The dump is debug-only, and the probe runs at
  startup.

### 1.4 DETECTION

#### D1. Truecolour the environment under-reports

- **What the code does, by reading** (TUIkitStyling/Color/ColorDepth.swift:231-282).
  It checks `COLORTERM` first, then `TERM`. `xterm-ghostty` and `xterm-kitty`
  contain neither `direct`, nor `256color`, nor `color`, so they fall to
  `.basic16`.
- **When it bites.** Locally, Ghostty sets `COLORTERM`. Over ssh, OpenSSH
  forwards `TERM` and not `COLORTERM`. So a Ghostty user who sshes into a box
  running a TUIkit app gets the **16-colour** rendering, the tier the owner
  calls "technical only".
- **A correction to the readers.** They predicted 256 colours. That is the
  case where something has rewritten `TERM` to `xterm-256color`, such as
  Ghostty's opt-in ssh integration.

Steps:
1. **TERM names (3 h).** Treat these `TERM` values as `.truecolor`:
   `xterm-ghostty` and `xterm-kitty`, plus `wezterm`, `alacritty` and `foot`,
   which are truecolour by their own documentation (unmeasured here). Unit
   tests in the `detect(environment:)` shape. This fixes the common case with
   no query.
2. **Probe (2 h).** Extend `identity_probe.py` to ask XTGETTCAP for `RGB` and
   `Tc` on identified non-Apple hosts. It needs no TUIkit code.
3. **Query (1 day; only if step 2 is positive and wanted).** Ask the same in a
   second exchange, when XTVERSION answered and the host is not tmux.
   - DCS must never reach Apple Terminal, which prints it (compat :539-541).
     Apple Terminal does not answer XTVERSION, so gating on that answer keeps
     it out.
   - Raising `ColorDepth.current` after identification is allowed: it happens
     before the first frame, and the render cache already clears when the
     depth moves (RenderCycle.md:460).

Measure with unit tests, then by hand: `ssh localhost` from Ghostty with
`COLORTERM` unset, looking at Example's Theme page.

#### D2. Facts for `Terminal-compatibility.md` (2 hours; each lands with the step that touches its section)

- **Mode 2027.** Ghostty's `grapheme-width-method` config explains the
  "supported, and off" state TUIkit already handles: it is what a user with
  `legacy` presents. Setting 2027 forces `unicode` width; resetting it hands
  back the user's config.
- **Mode 2031.** Ghostty documents it (features page, 1.0.1 and 1.3.0 notes).
  It reports theme flips, not OSC 10/11/12 changes. It is still unmeasured
  here, and TUIkit's re-ask on any 997 is right either way.
- **From Ghostty's source mode table:**
  - 2026 (synchronized output);
  - 2048 (`in_band_size_reports`, undocumented);
  - 1007 (`mouse_alternate_scroll`, **default on**: what A13's D0 hand-off
    relies on to keep the wheel);
  - 7 (wraparound, default on).
- **Per-sequence facts** (OSC 52, 22, 2, 9;4) land with their steps.

---

## 2. Overlaps with the SwiftUI-API queue: coordinate, don't duplicate

| SwiftUI item | Ghostty sequence | Relation | Action |
|---|---|---|---|
| Clipboard rule + A13 (decisions-text lane, `plan/wave_d4x.js`) | OSC 52, XTSHIFTESCAPE, mode 1007 | The lane owns the clipboard writer | Hand the lane C1's seven points before it launches (they become review items if it already has). C5 waits on A13's D1. |
| A4 kitty keyboard (in flight, worktree `wf_452f92d9-3ae-2`) | SS3 keys, CPR fence, teardown debt | Same files: `KeyEvent.swift`, `Terminal.swift`, `App.swift`, `FatalSignalTerminalRestore.swift` | K1, K2, K3, O1 and the dump half of K6 land **after** it. Every new mode joins its fatal-signal debt. |
| A5 interactive resize (decided: quiet-period inference) | Mode 2048 in-band size reports | Not a replacement | No change (below). |
| B53 Reduce Motion (decided: env + app-wide setting) | None | Ghostty documents no reduce-motion report | No change. |
| A16 colours / HDR (decided: graceful APIs only) | Colour concepts, OSC 4/10/11/21 | SDR everywhere | No change (below). |
| A28 chrome (decided) | OSC 2, OSC 9;4, OSC 9, BEL | A28 §9 names OSC 2 for a root `.navigationTitle` | Build the ledger and OSC 2 once, after A28 (C2). The A28 lane writes no OSC itself. |
| P15 `WindowGroup` titles | OSC 2, XTWINOPS 22/23 | Same work as C2 | C2 closes P15's title bullet. |
| OSC 8 links (shipped 2026-09-02) | OSC 8 | Already adopted and measured | K5's two fixes only. |
| O12 `PointerStyle` (open) | OSC 22 | O12's facts are partly wrong | Correct O12 when the owner reaches it; C4 is option (b) with per-host names. |
| `onHover` / `onContinuousHover` (shipped) | OSC 22 | C4 reuses their pointer tracking | None. |
| Colour queries and the root ground (`translucent-root-grounds`) | OSC 4, 10, 11, 21 | Queries already in use; the ground decision is open | No change; the OSC 11 *set* is Q6. |

Notes behind the rows:

- **A5.** Ghostty implements mode 2048 (`in_band_size_reports`, modes.zig)
  but documents it nowhere.
  - A report says `CSI 48 ; rows ; cols ; height_px ; width_px t`. That is a
    size, the same information SIGWINCH plus TIOCGWINSZ gives. It never marks
    a drag's start or end, so the owner's quiet-period inference is still the
    only way to synthesise `onInteractiveResizeChange`.
  - The mode's real value is elsewhere. It suits the WebAssembly port, which
    has no SIGWINCH (WebAssembly.md:146). It would also deliver the cell
    pixel size B42 needs, in-band and in order with input.
  - Its DECRQM is the unsafe shape on Apple Terminal, so it would be gated by
    identity, as 2027 is.
  - Not adopted now. Revisit with the wasm port.
- **A16.** Ghostty's colour specs are SDR: `rgb:` with up to 16 bits per
  channel, and `rgbi:` from 0 to 1. No sequence anywhere in the reference
  signals headroom.
  - The owner's "only APIs that fail gracefully; 'is HDR supported' = no"
    therefore stays true on every host, Ghostty included.
  - OSC 21's `@alpha` is opacity, not HDR.
  - Nothing here bears on A16's custom-provider benchmark.
- **The root ground.** The open owner decision is whether to spend a
  translucent root ground over the terminal's background. TUIkit already asks
  for that background with OSC 11 (TerminalColorQuery.swift:116). Ghostty
  confirms the reply format the parser already reads (4-digit `rgb:`), so the
  decision needs nothing new from this track.
  - Setting the terminal's own background (OSC 11, restored with OSC 111) is a
    different question: whether TUIkit may change the user's terminal
    colours. That is Q6.
  - Root grounds are painted explicitly on every frame (RenderLoop.swift:36),
    so the only visible gain would be Ghostty's window padding and the cells
    a live resize exposes.
- **A13 hand-off (D0).** The hand-off keeps the wheel through alternate-scroll
  mode 1007, which Ghostty turns on by default (modes.zig). Record this in the
  compatibility doc with A13's C0.
- **OSC 4 multi-pair queries.** Ghostty documents them, but the saving is
  about 90 bytes once per startup. Not worth a probe on its own (§3).

---

## 3. Decline

| Sequence(s) | Why not |
|---|---|
| REP `CSI n b` | A host that parses CSI but lacks REP silently drops cells. xterm repeats only characters below 256, so `─` would vanish. No DA bit reports it. M0's capture records run lengths, so it can be reopened on evidence. |
| ICH / DCH for in-line edits | Without DECSLRM they shift everything to the screen edge (borders, sibling panes), and hosts split wide characters differently. The span diff already writes only a field's tail. DCH stays only in Apple Terminal's card-measured surgery. |
| DECSLRM, DECLRMM (?69) | Valuable only on top of O2, for non-full-width panes. Apple Terminal and tmux lack it, which doubles the test matrix for a minority layout. Deferred until O2 has run for a while. |
| CUU, CUD, CNL, CPL, VPA, VPR, HPA, HPR, CHT, CBT, TBC, HTS | Relative or tab-stop motion saves 2–4 bytes over CUP and gives up absolute re-anchoring, which is load-bearing (images; containing advance divergence). Tab stops are terminal state TUIkit does not own. O3's CUF is the one relative move worth having. |
| IND, RI alone | Covered by SU/SD. IND stays as O2's fallback. |
| ED for vanished rows | One ED 0 would also erase the status bar, and the loop runs only when a frame shrinks. |
| RIS | Clears the primary screen, wiping the shell's output. K2 asserts the few defaults TUIkit depends on instead. |
| DECALN | A test pattern. |
| DECSCUSR | The caret is a drawn, breathing cell (owner, 09-26). The user's cursor shape cannot be restored: `0` is implementation-defined, and DECRQSS is a DCS that Apple Terminal prints. |
| LF/NL mode (20), LNM double Enter | No measured host or shell leaves mode 20 set. The fix is known if it ever appears: merge CR LF in `tryExtractPlainText`. |
| OSC 0, OSC 1 | OSC 0 equals OSC 2 on Ghostty. Keep it only as C2's fallback. Almost nothing implements OSC 1. |
| OSC 4 *set*, OSC 104 | Reprogramming the palette would shift the cube the image quantiser assumes, the colour re-ask would read back TUIkit's own values, a crash leaves the tab altered, and tmux forwards OSC 4 to one client only. |
| OSC 4 multi-pair query | ~90 bytes once per startup. |
| OSC 5, OSC 105 (special colours) | Slot 0 reveals only Ghostty's `bold-color`, not iTerm2's "brighten bold". `quantizeToANSI256` already avoids the hazard on every host. |
| OSC 7 (working directory) | A TUIkit app does not change the shell's directory. If a file browser ever wants new tabs to open where it is, add `.terminalWorkingDirectory(_:)` then (2–3 h). |
| OSC 10–19 / 110–119 *sets*, except Q6 | Ghostty ignores 13–19. Only xterm answers 17 and 19. |
| OSC 21 (kitty colour protocol) | OSC 10/11/4 already work on every host that answers OSC 21, and on more besides. Its stack is for apps that recolour the terminal. |
| Mode 2048 now | See §2 (A5). Revisit with the wasm port. |
| Mode 2027, 2031 code changes | Already right. Documentation only (D2). |
| C1 (8-bit) controls, BEL as a terminator, non-numeric OSC | TUIkit already sends ST, accepts BEL or ST in replies, and strips both C1 forms. |

---

## 4. Risks and loose ends

- **A hold left open.** A SIGKILL between the begin and end markers freezes
  Ghostty's display for up to a second (its timer). Other hosts' timeouts are
  unmeasured. `sync_probe.py` should time one per host by sending a begin
  marker with no end.
- **The fatal-signal debt is a fixed buffer**, allocated before the handlers
  are installed. Each new entry must be a reset that is harmless when nothing
  was set:
  - `?2026l`, `?7h`, `> 0 s` and `9;4;0` are harmless.
  - An OSC 22 reset is harmless only once the probe names a value that
    restores the shell's own pointer.
  - A title pop is harmless only where the host keeps a stack.
  Anything else stays out of the debt.
- **tmux** is unmeasured for 2026, 9;4, 22, 9 and XTSHIFTESCAPE. Each probe
  runs once under tmux 3.7c inside Ghostty and inside iTerm2.
- **Apple Terminal's row store** is the main unknown for O2 and K3. Both are
  card-gated, and the exclusions in O2 are the fallback.
- **The keep-alive wake (C3)** is the only item that adds a timer.
  `idle_cpu.py` must show zero renders while a bar is shown at idle.

---

## 5. Questions only the owner can answer

1. **Shift-click on Ghostty (XTSHIFTESCAPE).** While it is on, Ghostty users
   lose Shift-drag native selection in exchange for TUIkit's Shift-click range
   selection. Never; only while a Shift-click consumer has focus; or app-wide?
   *Recommend: only while focused now, app-wide once A13's drag-select ships.*
2. **Pointer shapes (O12).** Ship SwiftUI's `pointerStyle` with CSS names on
   Ghostty and X11 names on iTerm2, inert elsewhere, with built-in shapes over
   fields, links and dividers wherever the reset is measured clean?
   *Recommend: yes.*
3. **Progress.** Add a TUI-specific `.terminalProgress(_:)` (Ghostty draws a
   bar per split, iTerm2 probably too, inert elsewhere; ~1½ days)?
   *Recommend: yes.*
4. **Attention.** Add `\.requestAttention`, a desktop notification by OSC 9
   where honoured and BEL otherwise (~1 day)? *Recommend: yes, after
   progress.*
5. **Hardware scrolling.** Spend 3–5 days after A28 if the ½-day estimate
   shows at least 50% fewer bytes on scrolling? *Recommend: yes, at that
   threshold.*
6. **Setting the terminal's colours.** May TUIkit ever *set* the terminal's
   own colours? For example, OSC 11 to the app's background so Ghostty's
   window padding and resize gaps match, restored on exit; a SIGKILL would
   leave the tab recoloured. *Recommend: no, stay read-only. Revisit with the
   translucent-root-ground decision.*
7. **Landing order.** Run the four steps that conflict with no lane now, in
   one small lane, and serialise the rest behind the keyboard, text and A28
   lanes? *Recommend: yes.*

---

## 6. Staged plan: one commit per step, docs in the same commit

**Gates for every step:**
- the 6.2.4 build and the suite, with zero warnings;
- the Linux cross-compile for anything in TUIkitCore or TUIkitStyling;
- no POSIX in the four lower modules (G2 hands the hostname in);
- `Stress --selfcheck` for drawing steps (V2, V5, V11, V12);
- CPU A/Bs (`emit_bench.py`) only by the owner, on a quiet box. Agents capture
  bytes only.

**Terminals:**
- Apple Terminal 455.1, iTerm2 3.6.11, Ghostty 1.3.1, Warp, kitty;
- tmux 3.7c inside Ghostty and inside iTerm2.

They are driven by the standing terminal-apps permission: Ghostty by
`open -na Ghostty.app --args -e`, Warp by a launch configuration. Every probe
stamps its output with `probe_stamp.py`.

**Lanes and their files** (as of `697d9ef48` and the lanes' worktrees):
- **Keyboard lane** (in flight): `App.swift`, `Terminal.swift`,
  `Terminal+Input.swift`, `Terminal+KeyboardProtocol.swift`, `KeyEvent.swift`,
  `InputHandler.swift`, `RenderLoop.swift`, `FatalSignalTerminalRestore.swift`
  (new), and `Terminal-compatibility.md` (13 edits).
- **Decisions-text lane** (queued; planned files, not verified):
  `SystemClipboard.swift`, the text handlers' clipboard files,
  `TerminalHost.swift`, a clipboard support table, `RenderLoop.swift` (the
  OSC 52 drain), `MouseEventDispatcher*`, `MouseSupport.swift`, and
  `Terminal-compatibility.md`.
- **A28 lane** (decided, not launched): `RenderLoop.swift`,
  `FrameDiffWriter.swift` (regions), `Scene.swift` / `WindowGroup`,
  `StatusBar*`, `AppHeaderState`.

### Phase 0 — coordinator, now (no lane)

| Step | What | Files |
|---|---|---|
| G0 | Commit this study as `Documentation/Ghostty-VT-reference-review.md`, a new file, so nothing conflicts | that file |
| — | Add C1's seven points to the decisions-text lane's brief (`plan/wave_d4x.js`), or to its reviewer's checklist if it has launched | session notes |
| — | Tell the A28 lane: no OSC 2 of its own; route the root `.navigationTitle` to the ledger (C2) | session notes |
| — | When the owner reaches O12: the three factual corrections (C4) | `SwiftUI-API-completion-refusal-review.md` |

### Phase 1 — a small lane now, alongside the SwiftUI lanes

| Step | What | Files | Tests | Terminals / probe |
|---|---|---|---|---|
| G1 | D1 step 1: TERM names that mean truecolour | `Sources/TUIkitStyling/Color/ColorDepth.swift`, its detect tests | `detect(environment:)` table; `xterm-ghostty` without `COLORTERM` is `.truecolor` | Ghostty and kitty via `ssh localhost` with `COLORTERM` unset (by hand) |
| G2 | K5: host-named `file://` links; skip URIs over 2083 bytes | `Sources/TUIkitCore/Extensions/TerminalHyperlink.swift` (takes the host name), `Sources/TUIkit/Rendering/TerminalHyperlinkSupport.swift` (reads `gethostname` once), hyperlink tests, the compat doc's OSC 8 section | openings for `file:` with no host, `localhost`, an explicit host; the cap | `hyperlink_probe.py` with `file://` rows: Ghostty, iTerm2, kitty |
| G3 | K4: DSR 5 fences | `TerminalIdentityQuery.swift`, `TerminalModeQuery.swift`, `TerminalGraphicsQuery.swift`, their tests, `Tools/Smoke/identity_smoke.py`, compat doc identity section | each parser ends on `CSI 0 n` and passes over an interleaved `CSI 1;2 R` | `identity_probe.py` on four hosts, tmux, screen |
| G4 | K6, probe half: `ESC 7` / `ESC 8` in the graphics probe | `TerminalGraphicsQuery.swift`, its test | request bytes pinned | graphics probe re-run on Ghostty, Apple Terminal (nothing printed) |
| M0 | Measurement tooling for O2 and O3: step markers in dumps; `--shift` and `--runs` analyses | `Tools/Profiling/drive.py`, `Tools/Profiling/analyze_stream.py`, `Tools/Profiling/README.md` | `test_drive.py` covers the markers | none (captures of `tour`, `splitdrag`, `table`, `scroll`, `list`; numbers go in the commit message) |

**Conflict notes.**
- G1, G2, G4 and M0 touch no file any SwiftUI lane touches.
- G3 avoids the keyboard lane's files. Its compatibility-doc hunk sits in the
  identity section, which the keyboard lane may also edit, so integrate by
  cherry-pick and resolve as a union (the append-append memory).
- G2: the decisions-text lane may generalise the hyperlink ladder for its
  clipboard table. If it launches first, rebase G2.

### Phase 2 — after the keyboard lane lands

| Step | What | Files | Tests | Terminals / probe |
|---|---|---|---|---|
| V1 | K6, dump half: `ESC 7` / `ESC 8` and `forgetTerminalStyling()` after the dump | `Sources/TUIkit/Rendering/Terminal.swift` | dump bytes through the write seam | none |
| V2 | O1: synchronized output around multi-row frames | `Terminal.swift` (reserve/flush, error path, `disableRawMode`), `RenderLoop.swift` (one call after the graphics write), `FatalSignalTerminalRestore.swift` (debt), compat doc, new `Tools/TerminalProbes/sync_probe.py` | multi-row frame wrapped once; single-row frame unwrapped; empty frame writes nothing; marker after graphics; end marker in teardown and debt | `sync_probe.py` on four hosts and tmux; Ghostty by eye on `splitdrag`; bytes on `tour` and `splitdrag`; owner: `emit_bench.py` on `animating`, `scrollfollow`, `kitchensink` |
| V3 | K2: assert the inherited defaults | `Terminal.swift` (`enableRawMode`) | `enableRawMode`'s bytes pinned; each sequence's shape asserted Apple-safe | pre-set region and origin mode, then Example, on four hosts and tmux |
| V4 | K1: SS3 application keys | `Sources/TUIkitCore/Input/KeyEvent.swift`, `KeyEvent` and split-invariance tests, compat doc numeric-pad paragraph | every SS3 spelling, split at every byte; keypad digits carry `.numericPad` | `printf '\e[?1h\e='` then Example on four hosts; a PTY smoke |
| V5 | K3: autowrap off; peak guard for custom quirks | `Terminal.swift`, `FatalSignalTerminalRestore.swift`, `String+ANSISplitting.swift` call site, compat doc | enable and restore bytes; debt; custom-quirks clip | an over-wide last-row card on Apple Terminal first, then iTerm2 (ambiguous-wide), Ghostty, Warp, kitty, tmux; `Stress --selfcheck` |

V1, V3 and V5 all touch `Terminal.swift`, so they run in sequence in one lane.
V2's `RenderLoop.swift` line sits in `writeFrame`, near the decisions-text
lane's OSC 52 drain. Land V2 before that lane launches, or after it lands.

### Phase 3 — after the decisions-text lane (A13) lands, and Q1

| Step | What | Files | Tests | Terminals / probe |
|---|---|---|---|---|
| V6 | C5: XTSHIFTESCAPE while a Shift-click consumer is focused | `Sources/TUIkit/App/MouseSupport.swift`, `Terminal.swift` (`applyMouseSupport`), the consumers' registration (List selection, TextField, TextEditor mouse handlers), `FatalSignalTerminalRestore.swift`, compat doc | `> 1` / `> 0` follow focus; teardown and debt; `TUIKIT_SHIFT_CLICKS=0` | `mouse_probe.py` Shift-clicks with and without on Ghostty, Warp, iTerm2, Apple Terminal (CPR leak check), kitty |

### Phase 4 — after A28 lands (and Q2–Q5)

| Step | What | Files | Tests | Terminals / probe |
|---|---|---|---|---|
| V7 | The ledger plus C2's window title (P15's `WindowGroup` titles; a root `.navigationTitle` per A28 §9) | new `Sources/TUIkit/Rendering/TerminalHostState.swift`, new `Sources/TUIkit/App/RenderLoop+HostState.swift`, `App.swift` (suspend, cleanup, resume), `Scene.swift`, `FatalSignalTerminalRestore.swift`, the capability environment value, `Tools/APIParity` baseline, map and corpus, compat doc | change-only writes; sanitiser (BEL, ESC, C1 in a title); push/pop around suspend; SwiftUI-shaped corpus | new `title_probe.py` on four hosts and tmux |
| V8 | C3: progress (Q3) | new `Sources/TUIkit/Modifiers/TerminalProgressModifier.swift`, the ledger, the run-loop timed wake, compat doc, new `progress_probe.py` | states and clamping; keep-alive without renders; teardown | `progress_probe.py` on Ghostty, iTerm2, kitty, tmux; `idle_cpu.py` with a bar shown |
| V9 | C4: pointer shapes (Q2) | new `PointerStyle.swift` and `PointerStyleModifier.swift`, new per-host name table beside `TerminalHyperlinkSupport.swift`, `MouseEventDispatcher` (region resolution), the ledger, parity map (refusal removed), baseline, corpus, compat doc, new `pointer_probe.py` | topmost style wins; change-only writes; reset on exit and suspend; inert on unidentified hosts | `pointer_probe.py` with screenshots: Ghostty, iTerm2, kitty, tmux |
| V10 | C6: attention (Q4) | new `RequestAttentionAction.swift`, the ledger's write queue, compat doc | ConEmu guard; sanitiser; BEL fallback outside strings | four hosts and tmux, by eye |
| V11a–d | O3: the four trims, one commit each, each kept only on its M0 number | `Sources/TUIkit/Rendering/FrameDiffWriter.swift`, `Sources/TUIkitCore/Extensions/String+CellSpanDiff.swift`, golden snapshots | decomposer fill after a head `K`; span planner; goldens | bytes per M0; Apple Terminal light-profile card; owner: `emit_bench.py` on `textwall`, `kitchensink`, `table` |
| V12 | O2: hardware scrolling (Q5) | `FrameDiffWriter.swift` (band detection and cache rotation), `Documentation/Terminal graphics protocols.md` (its "no scroll region" sentence), compat doc | band detection table; cache rotation equals a fresh build; replay rows excluded; split invariance | scroll cards on Apple Terminal (light and dark), iTerm2, Ghostty, Warp, kitty, tmux; bytes on `scroll` and `list`; owner: `emit_bench.py` on `scrollfollow`, `scrolleager`, `megalist`, `kitchensink` |
| V13 | D1 step 3: XTGETTCAP `RGB` (only if the G-phase probe is positive) | `TerminalIdentityQuery.swift`, its tests, compat doc | sent only after XTVERSION and never under tmux; parse | `identity_probe.py` on four hosts and tmux |

V7–V10 share the ledger, so they run in sequence. V11 and V12 share
`FrameDiffWriter.swift`, so they run in sequence too. The two chains share no
file and could run in two lanes, but the owner prefers one landing stream, so
the default is V7 → V8 → V9 → V10 → V11 → V12.

**Cost by phase:**

| Phase | Cost |
|---|---|
| 0 | ~1 h |
| 1 | ~1½ d |
| 2 | ~2 d with cards |
| 3 | ~1 d |
| 4 | ~10 d, 4½ of them V12 |

These are agent days, not counting the owner's quiet-box A/Bs.
