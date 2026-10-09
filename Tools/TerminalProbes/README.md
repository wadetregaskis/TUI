# Terminal probes

Reproducible measurement tools behind `Documentation/Terminal-compatibility.md`.
Run each INSIDE the terminal under test; the recording probes (advance,
mouse) write to `$PROBE_OUT` (mouse falls back to `./mouse_probe.log`
when unset), the visual/aspect probes print to the terminal.

- `advance_probe.py` — DSR (`ESC[6n`) cursor-advance measurement of a
  grapheme-cluster battery + terminal-relevant environment dump (JSON).
  `PROBE_ALT=1` measures on the ALTERNATE screen (the app's buffer) —
  iTerm2 advances some clusters differently there.
- `page_clusters_probe.py` — measures every distinct cluster an APP ACTUALLY
  DRAWS, rather than a hand-picked battery: the battery only contains what
  somebody already thought to doubt. **This is the check that separates
  "consistent" from "correct".** Verifying rows against each other cannot:
  the framework and the model share the same numbers, so a model that is wrong
  about the terminal produces rows that add up perfectly and still render
  wrong. Verified — with Warp's Plane-16 case removed, every row still summed
  to the terminal width while every SF Symbol sheared a cell. Found three real
  shears on 2026-08-26 that no unit test saw.
- `probe_stamp.py` — not a probe: the shared provenance stamp every probe
  result carries (date, OS, terminal version, screen buffer, and DEC mode 2027,
  the two conditions this project has been bitten by not recording). It asks
  DECRQM for mode 2027 — and skips it on Apple Terminal, where that query's
  final byte prints to the screen and would move the cursor out from under the
  measurements that follow.
- `data/` — the committed measurement records, one per (terminal, version,
  screen). Written by a probe, never by hand. See `data/README.md`.
- `bidi_card.py` — static `|<sample>|X` alignment card for RIGHT-TO-LEFT
  text, printed twice: plain, and with each RTL run wrapped in
  U+202D … U+202C. Rows whose `X` moves are painted at a width TUIkit did
  not count; whether the host also REORDERS is read off the
  `digits_after_rtl` row instead (the X cannot see it — see the card's own
  closing lines). Run in all four hosts 2026-09-01; the results and what
  they settled are in Terminal-compatibility.md's "Right-to-left text"
  section.
- `rtl_image_card.py` — the same question asked of a PICTURE rather than of a
  line of text: a gradient drawn from a ten-letter Hebrew ramp, printed five
  ways (an ASCII control, plain, a colour change per cell as a render emits,
  U+200E after each cell, and every cell written after an `ESC[nG` column
  move). Every row has a FLAT RUN of one repeated glyph at its left; reversing
  a row moves it to the right, which is legible without reading Hebrew.
  **Its first version measured nothing** — it drew the staircase from ONE
  repeated letter, and a run of identical characters looks the same reversed —
  which is the lesson: a card about ordering has to be made of things that can
  be told apart. MEASURED on Apple Terminal 2026-09-01: `hebrew`, `coloured` and `positioned`
  all mirrored, `lrm` correct with the alignment column unmoved — but emitting
  the mark for real DESTROYED the Image page, so `lrm+coloured` and `lrm+wide`
  were added for the two axes that block lacked. STILL OPEN — see
  Terminal-compatibility.md's "RTL characters as image PIXELS".
- `breath_card.py` — how a host paints TUIkit's reversing row breaths: at 16
  colours, a cursor row whose breath runs between a slot fill and reverse video
  (the whole row the text's colour, every glyph on it the page's); without
  colour, reversal on every frame and bold on the bright ones. The rows are the
  bytes the framework emits (captured 2026-09-30, Red Sands on xterm's sixteen),
  so it needs nothing built; `--animate` plays each breath at its 50 ms cadence.
  `--host ghostty` swaps in the frames for a default-config Ghostty's own
  sixteen (derived from rule.py, not captured): a host that reports its table
  gets fills placed against it, and xterm's picks replayed there mislead. Read
  on all four hosts 2026-09-30 — see "A 16-colour row breath" in
  `Documentation/Terminal-compatibility.md`. Launch it from outside `~/Documents`
  in Ghostty (copy it to a temporary directory first): Ghostty has no access to
  that folder here, and the script's own open waits on a consent prompt.
- `overhang_card.py` — does a chrome glyph's INK stay inside its cell? Each of
  the 34 `chrome_key`/`chrome_glyph` corpus rows is drawn in ONE cell between
  two flanks of solid magenta; ink on a flank is overhang, and which flank says
  which way. The alignment cards cannot ask this — they measure where the next
  character lands, and an overhanging glyph moves nothing: the grid is intact
  and only the ink is over the line, which is exactly the `↵ activate` →
  `↵activate` report from Ghostty. Two calibration rows (`█` must meet both
  flanks, `a` must clear them) say whether the card is legible on the host
  before any row under them is believed, and a third block draws the reported
  shape (`<glyph> label` beside `<glyph>  label`) so the remedy can be judged
  where the defect was seen. **READ on all four hosts 2026-09-04**, and the
  answer is per host: Ghostty smears `↵` alone, Warp smears `⎋ ⏎ ⌫ ⌦ ␣ ⌥ ⌘`
  and NOT `↵`, Apple Terminal and iTerm2 smear nothing, and no drawing glyph
  smears anywhere. The five keyboard symbols added 2026-10-05 (`↩ ↖ ↘ ⇞ ⇟`,
  the keys' macOS symbols, drawn for the first time) were not on that card and
  are UNREAD on every host — `↩`, which replaced `↵` as Return, first on
  Ghostty. The mechanism it feeds is
  `TerminalWidthTraits.chromeOverhang` with the sets in
  `Sources/TUIkitCore/Extensions/ChromeOverhang.swift`; the reading is written
  up in Terminal-compatibility.md, "The ink half". Record the FONT and its size
  with the host — overhang is a font property at least as much as a host one,
  and the 2026-09-04 reading did NOT capture it, which is the one gap in it.
- `visual_card.py` — static `|<c>|<c>|<c>|X` alignment card with a column
  ruler, for screenshot inspection of PAINTED width (which DSR can't see),
  merged-vs-split clusters, seams, and swatches. It answers exactly ONE of a
  row's four facts — paint. DSR (advance) governs when the row WRAPS, the
  landing governs where followers go, and the store governs later absolute
  writes: on Apple Terminal a ZWJ sequence paints 2 while DSR reports 5/8/11,
  and a full-width row budgeted at the painted 2 really does wrap (measured
  2026-08-26; an earlier note here concluded "rows do not shear" from the
  paint alone, and was wrong). Confirm a divergence with the wrap test and
  `landing_probe.py`/`treatment_card.py` before compensating — no single
  instrument settles it.
- `background_probe.py` — does the cell an under-advancing cluster's `CUF`
  skipped keep the background in force? Draws each compensation strategy as a
  RUN of clusters, so a one-cell hole reads as stripes on a screenshot, and
  DSR-measures the advance of each at the same time. `PROBE_WIDE=1` draws the
  rows double-width (DECDWL) for the capture.
- `mouse_probe.py` — raw-mode SGR mouse byte capture (1000/1002/1006);
  every input sequence is appended human-readably. `q` quits.
- `keyboard_protocol_probe.py` — does the terminal speak the kitty keyboard
  protocol, and which of the five flags TUIkit pushes (31) does it take? Asks
  exactly as TUIkit does — `CSI ? u` fenced by DA1 — then pushes 31, asks
  again, pops and asks a third time; JSON to `$PROBE_OUT`. `PROBE_ALT=1` does
  it on the alternate screen, where TUIkit does it.
- `keyboard_events_probe.py` — with those flags pushed, what each key sends:
  every read logged raw and decoded by a decoder written from the
  specification, independently of TUIkit's `KittyKeyDecoder`. Ctrl-C ends it;
  the flags are popped on the way out. Which keys to press is listed in
  Terminal-compatibility.md, "The kitty keyboard protocol" → "To measure, per
  host". NOT YET RUN on any host (2026-10-04).
- `key_probe.py` — the LEGACY encoding (no keyboard protocol pushed): asks
  for each key a sheet's grabber binds or its design rejected (↖ ↘ ⇞ ⇟, ↑ ↓,
  ⌃↑ ⌃↓, ⇧↑, ⌥↑) in turn and records the bytes that arrived, decoded, or that
  NOTHING did within `PROBE_WAIT` seconds (6) — a host that keeps a key for
  its scrollback, or macOS taking ⌃↑ ⌃↓ for Mission Control. Run from the
  host's default profile, on both screens (`PROBE_ALT=1`), and note by hand
  whether the Mission Control shortcuts are on. JSON to `$PROBE_OUT`. See
  Terminal-compatibility.md, "Keys a sheet's grabber uses". NOT YET RUN on
  any host (2026-10-06).
- `sync_probe.py` — synchronized output (DEC mode 2026), which TUIkit wraps
  every multi-row frame in. Checks that `CSI ? 2026 h` `CSI ? 2026 l` prints
  nothing (the cursor column before and after), asks DECRQM `?2026$p` of a
  host that identifies itself (never of Apple Terminal, which prints that
  query's `p`), and records tmux. `--hold-timeout` then opens a hold and never
  ends it while a counter runs for 8 seconds: the first value seen is the
  host's timeout, read by eye or from a recording. JSON to `$PROBE_OUT`;
  `PROBE_ALT=1` for the alternate screen. NOT YET RUN on any host
  (2026-10-05).
- `clipboard_probe.py` — does the terminal put an application's OSC 52 write
  on the clipboard? Writes a nonce exactly as TUIkit spells it
  (`ESC ] 52 ; c ; <base64> ESC \`) and reads the clipboard back with this
  machine's helper (`pbpaste`, `wl-paste`, `xclip`, `xsel`), so a local run
  needs no person; `--manual` asks for a paste instead, for a run over ssh.
  Also: DA1 and whether it carries `52`, BEL and an empty selector, the
  largest copy that arrives whole (1 KiB to 1 MiB), and tmux's
  `set-clipboard` with whether tmux kept the write as a buffer.
  `--destructive` adds the empty and the non-base64 payloads, which Ghostty
  documents as CLEARING the clipboard. The clipboard is saved before the
  first write and put back however the run ends, where a helper can write
  it; a clipboard holding anything but text (a picture, files, rich text —
  which is what text copied from Safari or Notes is: copy plain text first,
  `printf probe | pbcopy`), or whose types cannot be listed, stops the run
  before anything is written unless `--clobber` says it may be lost. An
  empty X11 or Wayland clipboard is empty, not unlistable. With no helper to
  read the clipboard (over ssh without `--manual`), `--clobber` still takes
  the leak check, which needs no reader. `test_clipboard_probe.py` pins
  those rules (`python3 -m unittest test_clipboard_probe`, no terminal
  needed; CI runs it). JSON to `$PROBE_OUT`; `PROBE_ALT=1` for the
  alternate screen. NOT YET RUN on any host (2026-10-05): Ghostty, iTerm2 with
  its clipboard setting on and off, Apple Terminal, Warp, kitty, and tmux with
  `set-clipboard on` and `external` are owed.
- `identity_probe.py` — asks the terminal WHO it is over escape queries
  (DA1/DA2/DA3, XTVERSION, XTGETTCAP), DSR-fenced so a silent terminal
  cannot stall it. This is the measurement behind identifying a host over
  ssh, where `TERM_PROGRAM` does not survive the hop.
- `hyperlink_probe.py` — is OSC 8 SAFE to emit here? A terminal with an OSC
  parser swallows the whole sequence whether or not it implements the
  command; one without prints the URI as text and leaves the cursor
  wherever that ended. DSR sees the difference: a known-width label wrapped
  in OSC 8, against the same label bare. Both screen buffers every run, and
  an `unknown_osc` control so a "swallowed" result reads as a property of
  the host's parser rather than of this one sequence. Whether the host
  HONOURS the link — hover, ⌘-click — no query reports, so the probe prints
  a card for a person and records their answer beside the measurement
  instead of pretending to have derived it.
- `graphics_probe.py` — Sixel, the iTerm2 inline-image protocol and the Kitty
  graphics protocol: what the host advertises (DA1's Sixel parameter, Kitty's
  `a=q` handshake, and a *virtual placement* probe — the feature a TUI actually
  needs), and what its cursor does when sent one of each. The safety half is the
  same DSR question `hyperlink_probe.py` asks, and it has a different answer per
  family: **Apple Terminal parses OSC and PRINTS DCS and APC**, so a
  string-terminated escape is not automatically safe. Whether a picture actually
  appeared is a question about pixels, so the probe draws a card and asks. The
  analysis and the recommendation are in
  `Documentation/Terminal graphics protocols.md`.
- `placement_probe.py` — the follow-on question, and the one TUIkit's design
  rests on: with a *virtual* placement and Unicode placeholders, does a Kitty
  image behave like **cells**? It transmits a hue-ramp image, places it, writes
  the placeholder rows, and asks DSR how far the cursor moved — because
  U+10EEEE sits inside the Plane-16 PUA that this framework paints two cells
  wide and compensates for, and an image that inherited that rule would shear.
  Measured 2026-09-02: **one column per cell on all three hosts that answered**,
  Apple Terminal included. Also measures the run-length elision, both id
  encodings (256-colour and direct), delete-by-id, and what a full-screen
  transmit costs in bytes and milliseconds. Skips the big transmit on a
  terminal that answered no Kitty query — Apple Terminal would print it.
- `graphics_compression_probe.py` — does a **deflated** transmission (`o=z`,
  RFC 1950 before base64) reach the screen? Asks TUIkit's own two handshake
  questions — a virtual placement, then the 32×32 block sent as twenty-six
  deflated bytes, sized so a terminal that ignored the key would have to
  refuse it — and then draws the same hue ramp raw and deflated, one under
  the other, for a person to compare. "Acknowledged" and "drawn" are
  different facts about a terminal, and the JSON records the first and asks
  for the second. Unmeasured on every host as of 2026-09-04; the rows in
  `Documentation/Terminal-compatibility.md` ("Deflated transmissions") are
  waiting on it.
- `pixel_format_probe.py` — the question `OK` does not answer: which
  transmissions does a terminal actually **draw**? `placement_probe.py`
  established that iTerm2 acknowledges every graphics command — including a
  real `ENOENT` for a placement after a delete, so it genuinely tracks images
  — and then composites nothing. Two things differ between the exchange it
  acknowledges (the startup handshake: `f=32`, one escape, no `m` key) and the
  ones it ignores (a real picture: `f=24`, chunked `m=1` … `m=0`), and they
  travel together everywhere measured, so neither is ruled out. This transmits
  the same ramp four ways — `{f=24, f=32}` × `{single escape, chunked}` — and
  places each, so which letters appear names the cause. No reply to read: the
  question is what a human can see, so it prints a card and asks.
- `placeholder_spelling_probe.py` — how must a placeholder CELL be spelled
  for a terminal to draw it? `pixel_format_probe.py` had established that
  iTerm2 acknowledges everything, draws a direct placement, and drew nothing
  for a virtual one; "placeholders unimplemented" was one explanation and this
  tested a cheaper one. TUIkit then wrote TWO combining marks per cell — row
  and column — and omitted the third, which states the image id's high byte
  and which the spec lets a cell inherit from its left neighbour; a decoder
  carrying a sentinel for "absent" rather than zero would look up an image
  that was never sent. Crossed with the foreground spelling (24-bit against
  the 256-colour form kitty's own doc example uses), that is a 2x2: one image,
  one placement, four spellings of the cells that summon it. **Verdict
  (iTerm2 3.6.11, 2026-09-03): the two-mark cells draw nothing and the
  three-mark cells draw the picture, under either foreground spelling.** The
  encoder has written all three marks on every cell since 0d4d2015. The probe
  also reports what U+10EEEE advances the cursor by; iTerm2's line was never
  captured, so `Terminal-compatibility.md`'s advance table still omits it.
- `hairline_probe.py` — can a Kitty **classic** placement (not a placeholder)
  draw a line one or two pixels thick exactly on the boundary between two text
  rows, so a list separator costs no row? Runs on the alternate screen and
  asks ten questions: is the placement acknowledged AND drawn on the boundary
  (Q1); does `C=1` hold the cursor (Q2); is the placement's pixel unit
  TIOCGWINSZ's, `CSI 14 t`'s or `CSI 16 t`'s, and which crop width ends
  exactly at the end of a run that stops short of the window's edge (Q3, which
  then crops every later line by the unit it found); does `z=-1` show over
  fills and under glyphs (Q4); do `ESC[2K`, an overwrite and ECH keep the line
  (Q5); can one line be deleted by `(i, p)` and placed again without
  re-sending (Q6); does a line moved every frame tear, with and without mode
  2026, through `sync_probe.py`'s helpers (Q7); what `ESC[2J` and `?1049l/h`
  do to a line, and whether the image store is one per screen or the switch
  freed it (Q8); resize (Q9); and SGR 4 + 58 as the fallback without graphics
  (Q10). Each pixel question is a card a person answers with `y`/`n`/`s` (Q9
  with `y`/`m`/`g`/`s`, and Q7 adds `r` to run its animation again); Ctrl-C
  stops a run at any point. Every reply is read with `q=0` behind a DSR fence,
  and an id never sent is placed first as a negative control. `--auto` runs
  the automatic checks alone, for a run nobody watches. JSON to `$PROBE_OUT`,
  by default `data/<host>-<version>-hairline.json`, with this host's half of
  each kill criterion in `criteria`. Refuses Apple Terminal, and sends no
  graphics beyond the `a=q` question to a host that does not answer it (that
  host gets the Q10 card alone). Run 2026-10-08 in Ghostty 1.3.1 and iTerm2
  3.7.3 (`data/ghostty-1.3.1-hairline.json`, `data/iterm2-3.7.3-hairline.json`):
  neither host meets a kill criterion. Ghostty needs `z=+1`, iTerm2's pixel
  unit is unknown, and one Ghostty question is OPEN. The findings are in
  `Terminal-compatibility.md`, "A line on a row boundary".

  ```sh
  python3 hairline_probe.py          # the checks, then the cards
  python3 hairline_probe.py --auto   # the checks alone
  ```
- `cell_aspect_probe.py` — the terminal cell's height:width ratio (what
  `Image` needs to render undistorted), via `TIOCGWINSZ` pixel fields and
  the `CSI 14t`/`18t` escape queries. Report to `$PROBE_OUT` (default
  `./cell_aspect_probe.txt`); stdout stays attached to the terminal for the
  queries themselves.

`palette_probe.py` asks a different question from the rest: not how the cursor
moves, but what colour the terminal actually paints for a name we emit. The
sixteen ANSI colours are slots in the user's scheme, so `SGR 31` is "red" only
by convention — and TUIkit's contrast floor and 256-colour quantiser both
derive from a table of what those slots conventionally hold. Run it in each
host and record the answers in the compatibility document. What it takes to
ask those questions from inside an app (every host's reply spelling, latency,
fence ordering, and what tmux does in between) is `osc_colour_probe.py`'s
question; see its section below.

Extend the battery in `advance_probe.py` rather than hand-rolling one-off
probes, and record new results (with `TERM_PROGRAM_VERSION`) in the
compatibility document. (`Tools/EmojiBugScanner` is the Swift bulk variant of
the same DSR question — a GENERATED corpus of tens of thousands of clusters,
for sweeps the curated battery cannot cover; its 46k-cluster diff of the
quirks mirror against the hand-written model is how the missing skin-tone
erase was found. Prefer the battery for anything the corpus already names.)

A note on the PTY harnesses: `pyte` drops everything after a **U+FE0F** in the
same write (VS-16 is width 0 with combining class 0, so its `Screen.draw` hits
the `else: break`). A dump containing ⚙️ ⚠️ ✂️ ⚒️ therefore shows a truncated
row whatever the app emitted, which is a trap `tui_walk.py` and
`tui_screens.py` both sit in.

Two ways round it, and they answer different questions. For what a TERMINAL
draws, use the probes here, against the real host. For what the APP emitted,
use `Tools/Smoke/raw_probe.py`, which decodes nothing: it drives the app
through a key script and counts patterns in the bytes themselves — including
whether a cluster carried its cursor compensation, and `--term-program` to
force a host model from any terminal.

## `landing_probe.py` + `landing_analyze.py` — where the next character PAINTS

`advance_probe.py` asks the terminal where its cursor went. These two measure
where the glyph after a cluster is actually drawn, which is not the same
question and is the one a layout needs answered. Apple Terminal reports an
advance of 4 for 🤙🏽 and paints the next character two cells along; every model
built on the report put borders where nothing was drawn.

Run the probe inside the terminal under test:

```sh
PROBE_OUT=/tmp/landing.json PROBE_SHOT=/tmp/shot python3 landing_probe.py --wrap
```

then read the pictures:

```sh
python3 landing_analyze.py /tmp/landing.json -o data/<host>-<version>-alternate-landing.json
```

Prefer `PROBE_SYNC=1` and have **another process** take the screenshots (the
probe writes `<shot>.ready` and waits for `<shot>.done`). macOS asks the
terminal to confirm direct screen access and puts the dialog **over the window
being measured**, which hid a calibration mark for five runs. Without Screen
Recording permission the capture fails outright ("could not create image from
display 0") — grant it in System Settings, or fall back to the DSR halves
(`advance_probe.py` measures advance; `--wrap` here measures reserve) and
record the row in `TerminalLedgerConformanceTests.awaitingLandingMeasurement`
until the pixel halves can run.

Both clusters and expectations come from `data/width-corpus.json`, shared with
the Swift tests so a measurement always answers a question something asks.
`TerminalLedgerConformanceTests` is where the records are checked against the
models.

## `border_probe.py` — did any row shear, end to end?

The per-cluster probes say what a terminal does to one cluster in isolation.
This says whether the whole pipeline put the right edge where it belongs on a
screen full of real content: it finds the rightmost inked column of every
scanline and asks whether they agree.

```sh
screencapture -x /tmp/app.png
python3 border_probe.py /tmp/app.png
```

It crops to the app's own painted background first, so the desktop and other
windows cannot contribute an edge, and exits 1 on any outlier — so it can gate a
smoke run rather than only inform one.

## `matrix_probe.py` + `matrix_analyze.py` — the whole truth table in one run

Every corpus cluster × every applicable emission strategy (verbatim, `CUF`,
`ECH+CUF`, `CUB`, `CUB+CUF`, software strip, and the detach candidates: ZWNJ,
DECSC/DECRC separator, SGR separator, absolute positioning), measured in a
single run inside the terminal under test:

```sh
PROBE_OUT=/tmp/matrix.json python3 matrix_probe.py                 # DSR phase
PROBE_OUT=/tmp/matrix.json PROBE_SHOT=/tmp/mx PROBE_SYNC=1 \
    python3 matrix_probe.py                                        # + pixels
python3 matrix_analyze.py /tmp/matrix.json -o data/<host>-matrix.json
```

The DSR phase needs no display and answers, per (cluster, strategy): the net
internal advance, and whether a full-width row wraps — budgeted BOTH at the
composed claim and at the strategy's own advance, because a detach strategy's
premise is that the layout would claim its wider extent. The pixel phase adds
where the next character paints, the glyph's ink, and an APPEARANCE
classification (composed / stripped / detached / other) computed by comparing
each cell against reference glyphs rendered in the same run — no human reads
the screenshot.

Strategies are built from the cluster's advance measured live in the run, not
from a model, so the probe works unchanged on a terminal nobody has measured.

(`row_probe.py`, retired 2026-08-28, asked phase A's wrap question for four
clusters by hand; the matrix asks it for every corpus cluster × strategy.)

## `treatment_card.py` — the shipped emissions, verifiable at a glance

Where `matrix_probe.py` explores every strategy, this shows only the ones the
walk SHIPS for Apple Terminal — each as an expect/actual row pair on a blue
background, so "is it right" is a vertical comparison a human (or a
screenshot diff) makes in seconds. Page 2 ends a full-width blue row with
each emission, which is the white-cells-at-the-row-edge and wrap check.

```sh
PROBE_OUT=/tmp/treatment.json python3 treatment_card.py
```

The DSR half is fully automatic: `PROBE_OUT` records, per row, the net
advance against the claim, where sequential followers ended, where an
absolute CHA landed, and (page 2) whether the row wrapped — each with an `ok`
verdict. The pixel half (alignment of `ab` and `X`, background holes, glyph
appearance) needs eyes or a capture.

Four generations of this card settled the 2026-08-27 treatments: it is how
the ZWNJ separation, the ZWJ decomposition and the flag/keycap `DCH` store
surgery were chosen over the cursor-move repairs they replaced. The emissions
here mirror `String.withTerminalAppCursorCompensation()`, and
`TerminalWidthTraitsTests` pins the same literals on the Swift side.

## `recent_emoji_sweep.py` — does this host's width table know the new emoji?

Fully automatic (no eyes needed): DSR-measures the cursor advance of every
emoji-presentation scalar in the 1FA70–1FAFF block — where new emoji land
version after version — plus controls, and reports the ones the host
advances 1 against the 2-cell claim.

```sh
PROBE_OUT=/tmp/sweep.json python3 recent_emoji_sweep.py
```

First run (2026-08-28, all four hosts): Warp v0.2026.07.08 advances exactly
the seven Unicode 16.0 additions (🪉 🪏 🪾 🫆 🫜 🫟 🫩) by 1 — its width
table is Unicode 15.1 — while Apple Terminal, iTerm2 and Ghostty advance
all 113 by 2. That measurement is `Character.unicode16Emoji`, consulted
through `Character.isUnicode16EmojiOlderTablesMiss` wherever a host's
`TerminalQuirks.preUnicode16WidthTable` says its table predates 16.0 (it
was Warp-specific until bc9dc5b8 generalised it). Re-run when a Unicode version ships,
when a terminal updates, or when one emoji misbehaves — the sweep costs
seconds and answers for the whole block; extend `SWEEP` when new emoji land
outside it.

## `osc_colour_probe.py` + `tmux_colour_harness.py`: asking a terminal for its colours

`palette_probe.py` records what a host says its colours are. These record what
it takes to ask: whether each of OSC 10, OSC 11, OSC 4 and `CSI ? 996 n` is
answered at all, how the reply is spelled and terminated, how long it takes,
whether it can land after the `CSI 6n` / `CSI 5n` fence sent behind it, whether
a batch costs one wait or one per query, and whether anything prints. Results
and their versions are written up in `Documentation/Terminal-compatibility.md`,
"What an ANSI colour actually paints". As with `palette_probe.py`, no records
are kept in `data/`.

Run the probe inside the terminal under test; it only queries and sets nothing:

```sh
PROBE_OUT=/tmp/osc.json PROBE_LABEL="Basic profile" python3 osc_colour_probe.py
python3 osc_colour_probe.py --summarise /tmp/osc.json
```

`osc_colour_selftest.py` runs the probe against a scripted terminal on a pty in
five modes (answering, BEL-only, late, silent, printing) and checks the record;
it exits 1 on any mismatch and takes about 20 s. It checks the probe and
measures no host. Run it after any change to the probe. It has been seen to
fail: making the probe call every reply "before the fence" fails the `late`
mode.

`PROBE_SUITE=m3m7` asks two different questions with the same machinery — DEC
mode 2031 (the terminal telling an app its palette changed) and the SGR 7
spellings — because both are sequences the framework emits and neither is a
colour query:

```sh
PROBE_OUT=/tmp/m3m7.json PROBE_LABEL=iterm2 PROBE_SUITE=m3m7 python3 osc_colour_probe.py
```

It is the one mode in which this probe SETS anything: mode 2031 and SGR
attributes, both reset on the way out. It also sends DECRQM, which is the shape
Apple Terminal prints — that is why `?25` is asked as a control, so a leaked
cell reads as the host's parser rather than as mode 2031 being special.
`selftest_m3m7.py` checks it against three scripted terminals (clean; an
Apple-like one that prints a `?`-plus-intermediate final byte and a DCS payload;
one that prints part of an SGR and reports late) and takes about a minute.
Results are in `Documentation/Terminal-compatibility.md` under "Colour-palette
update notifications" and "Reverse video (SGR 7)".

`tmux_colour_harness.py` measures tmux itself: a real tmux on a private socket
with no configuration, whose clients are ptys this script plays, with known
answers and every forwarded query logged.

```sh
PROBE_OUT_DIR=/tmp/tc python3 tmux_colour_harness.py clients --order AB   # ~90 s
PROBE_OUT_DIR=/tmp/tc python3 tmux_colour_harness.py clients --order BA
PROBE_OUT_DIR=/tmp/tc python3 tmux_colour_harness.py batch --client silent
PROBE_OUT_DIR=/tmp/tc python3 tmux_colour_harness.py batch --client answering
```

- `clients` attaches two clients with different colours, one silent on OSC 4,
  and runs the probe in the pane four times (first alone; both, second attached
  last; both, after the first typed; first alone again). It prints whose OSC
  10/11 the pane saw, what `?996n` got, and which client OSC 4 went to. Run both
  orders: "attached first" and "attached last" only separate when swapped.
- `batch` writes the startup batch, fg/bg alone, one slot and the multi-pair
  spelling, each fenced by `CSI 5n` with a marker line printed straight after.
  It records when the fence reply reached the pane, what came back, when the
  marker reached the client (whether tmux holds pane output while a query is
  pending), and what was forwarded.

**A scripted client must answer each query exactly once.** The throwaway
harness these replaced kept an unconsumed buffer and re-sent a stale OSC 4
reply whenever new bytes arrived, and that alone made the multi-pair spelling
look broken under tmux 3.7c: one slot, after 0.5 s. With one answer per query,
tmux forwards the spelling as three single queries and returns all three slots
in under a millisecond.

Two things these tools cannot do alone:

- **Two real emulators on one session** need two windows: start
  `tmux -L probe -f /dev/null new-session` in one terminal, run the probe in the
  pane, `tmux -L probe attach` from a second terminal, and run it again.
- **Some hosts need a person at the machine.** On 2026-09-14, launching Ghostty
  with `-e` and launching a quarantined Hyper both stopped at a confirmation
  dialog nobody clicked, so no probe ran. iTerm2 opened what looked like an
  alert. A record from the same launcher is timestamped 07:48, well after the
  attempt, and nobody noted who dismissed the window.

## `reverse_video_card.py`: what SGR 7 paints

Whether a terminal PRINTS anything for SGR 7 (reverse video), or advances text
differently under it, is a cursor question. On 2026-09-14 every host asked gave
the same answer: nothing printed, and text advanced as plain text. What a
reversed cell LOOKS like, no report can tell you, so this is a card for a
person. Each case is drawn beside a hand-swapped reference: the same colours
with foreground and background exchanged, and no SGR 7.

- `ESC[7m` over the terminal's default colours, and `ESC[7;1m` with bold. SGR
  cannot name a default colour, so these two references are built as 24-bit
  colour from the host's OSC 10/11 answer. A host that does not answer (GNU
  screen) gets no reference.
- `ESC[7;31;44m`, `ESC[7;38;2;10;20;30;48;2;200;200;200m` and, as an extra,
  `ESC[7;1;31;44m`: each has an exact reference.
- Extras: `ESC[K` (erase to end of line) while reversed, `ESC[27m` part way
  along, and a reversed pair ended by `ESC[0m`.
- Keys 1–6 park the terminal's own cursor on a reversed cell, a reference cell or
  the erased tail. That shows whether the cursor stays visible and the cell
  under it readable.

```sh
python3 reverse_video_card.py              # keys 1-6 move the cursor, q quits
python3 reverse_video_card.py --no-query   # no OSC 10/11 query
python3 reverse_video_card.py --hold 20    # no keys; exits after 20 s
```

It sets nothing on the host, and its only query is OSC 10/11, fenced by
`CSI 5n`. Record what you saw, with the host, its version and its colour profile
or theme, in `Documentation/Terminal-compatibility.md` under "Reverse video
(SGR 7)". Under Warp, also record `appearance.text.enforce_minimum_contrast`
(read it, don't change it). At its default, Warp may lighten a named foreground,
and that would show up as a mismatch in the named rows for a reason other than
SGR 7.

**Not yet read on any host (as of 2026-09-15).** It has only been run in a pty,
where nothing is painted. The cursor measurements above came from
`osc_colour_probe.py`'s `PROBE_SUITE=m3m7` steps, above.
