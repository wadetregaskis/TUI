# Measurement records

Written by a probe and never by hand. These are the evidence behind the
tables in `Documentation/Terminals/Terminal compatibility survey.md`. The doc explains what
the numbers *mean*; these say who measured what, when, and under which
conditions. Thirteen kinds of file live here:

- **`width-corpus.json`** — the shared cluster corpus: every cluster the
  probes measure and the Swift tests ask about, one id per row, duplicated
  scalar-for-scalar in `TerminalWidthCorpus.swift` (a parity test pins the
  two). A measurement always answers a question something asks.
- **`<terminal>-<version>-<screen>.json`** — ADVANCE records
  (`advance_probe.py`): DSR cursor reports for the curated battery.
- **`<terminal>-<version>-<screen>-landing.json`** — LANDING records
  (`landing_probe.py` + `landing_analyze.py`): per corpus row, all four
  facts — advance (DSR), landing and ink (pixels), reserve (the wrap test).
  These are what `TerminalLedgerConformanceTests` checks every model
  against, and the known-divergence ledger lives beside that suite. A
  corpus row no landing record has yet measured must be listed in the
  suite's `awaitingLandingMeasurement` set, so its absence cannot read as
  a pass.
- **`<terminal>-<version>-hyperlinks.json`** — OSC 8 SAFETY records
  (`hyperlink_probe.py`): the DSR column after a known-width label wrapped
  in each spelling of the sequence, on both screen buffers, against the same
  label bare. These say whether emitting the sequence is safe, which is a
  different question from whether the host honours it — no query answers
  that second one, so the `honoured` field is filled in by a person or left
  saying so. Every file carries an `unknown_osc` row: a command number
  nothing implements, which is what makes a "swallowed" result a property of
  the host's OSC parser rather than of this one sequence.
- **`<terminal>-<version>-graphics.json`** — GRAPHICS-PROTOCOL records
  (`graphics_probe.py`): what the host advertises for Sixel, the iTerm2
  protocol and Kitty, plus the cursor deltas after being sent one of each. The
  deltas answer "is it safe to emit", which has a different answer per escape
  FAMILY on the same host; `rendered` is the human half and stays
  `unmeasured` until somebody looks at the card.
- **`<terminal>-<version>-placement.json`** — PLACEMENT records
  (`placement_probe.py`): one Kitty image transmitted and placed through
  Unicode placeholders — the mechanism TUIkit ships — with the host's reply
  to each command, the cursor advance over a placeholder row, and the
  human-filled `rendered`. These are what the graphics design rests on; the
  iTerm2 third-mark finding of 2026-09-03 came out of this probe.
- **`<terminal>-<version>-hairline.json`** — HAIRLINE records
  (`hairline_probe.py`): a Kitty CLASSIC placement used as a thin line on a
  row boundary, on the alternate screen. Each question carries its `auto`
  readings (every reply's code, cursor reports, the pixel-unit advances, the
  image-store model) and its `human` answers, which say "not asked" in an
  `--auto` run; `criteria` holds this host's half of each kill criterion.
  `acknowledgement_control` is the reply to a placement of an id never
  sent (`ENOENT` expected; an `OK` there voids the store readings), and
  `missed_fences` lists each DSR fence that timed out and whether the
  probe got back in step (a reading skipped meanwhile says `not read: out
  of step`).
  Only a run a person answered to the end replaces a record that holds a
  person's answers; any other run is written beside it, as
  `…-hairline-aborted.json` when it was stopped and `…-hairline-auto.json`
  when it ran `--auto` or went unanswered. Two so far, both answered to the
  end on 2026-10-08: Ghostty 1.3.1 and iTerm2 3.7.3.
- **`<terminal>-<version>-title.json`** — WINDOW-TITLE records
  (`title_probe.py`): the DSR column after each title sequence TUIkit sends
  (`OSC 2`, the push and the pop of the title stack, a pop with nothing
  pushed, the report request) on both screens, and the title the host
  reports (`CSI 21 t`, or tmux's `#{pane_title}`) after a set, a push and a
  set, and a pop. The machine's name is recorded as `<hostname>`. Four so
  far, 2026-10-19: Apple Terminal 455.1, iTerm2 3.7.6 and Warp (none
  answers the report) and tmux 3.7c.
- **`<terminal>-<version>-clipboard.json`** — OSC 52 records
  (`clipboard_probe.py`): whether the write printed anything (the cursor
  before and after), the host's DA1 and whether it lists `52`, whether each
  spelling (ST, BEL, an empty selector) reached the clipboard as the helper
  named in `read_back` read it, the largest copy that arrived intact (sizes
  stop at the first that does not), and whether the clipboard was put back.
  Inside tmux, `tmux` holds `set-clipboard` and
  whether tmux kept the write as a buffer; the two tmux runs are named by
  that option, `…-clipboard-on.json` and `…-clipboard-external.json`.
  Six so far, 2026-10-19: Apple Terminal 455.1, iTerm2 3.7.6, Warp, Ghostty
  1.3.1 and tmux 3.7c twice.
- **`<terminal>-<version>-identity.json`** — IDENTITY records
  (`identity_probe.py`): the reply to each query a host could be identified
  by — DA1, DA2, DA3, XTVERSION, XTGETTCAP `TN` — and to the status report
  `CSI 5 n` TUIkit fences its exchanges with, and in `XTVERSION+DSR5` the
  replies to an XTVERSION with the status report behind it, in the order
  they arrived. Four
  so far, 2026-10-19: Apple Terminal 455.1, iTerm2 3.7.6, Warp and Ghostty
  1.3.1.
- **`<terminal>-<version>-m3m7.json`** — MODE 2031 and SGR 7 records
  (`osc_colour_probe.py` with `PROBE_SUITE=m3m7`): each step's request, the
  cursor before and after it, and every reply, DECRQM's and DECRQSS's
  among them. `python3 osc_colour_probe.py --summarise <file>` prints them
  a line per step. The colour queries' own records are not kept; this
  suite's are, since 2026-10-19. One so far: Ghostty 1.3.1.
- **`<terminal>-<version>-graphics-compression.json`** — DEFLATED
  TRANSMISSION records (`graphics_compression_probe.py`): the replies to
  the startup handshake's virtual placement and its deflated 32×32 block
  (`o=z`), and to the same hue ramp displayed raw and deflated. `rendered`
  is the human half — whether the two ramps drew the same — and says
  `unmeasured` until somebody fills it in. One so far, 2026-10-19: Ghostty
  1.3.1.

- **`<terminal>-<version>-progress.json`** — PROGRESS-BAR records
  (`progress_probe.py`): the DSR column after each progress report TUIkit
  sends (`OSC 9 ; 4` with each state, with and without a value, and the
  removal) on both screens, and, inside tmux, the pane's bar as tmux keeps it
  (`#{pane_pb_state}`, `#{pane_pb_progress}`) after each; with `--timeout`,
  the bar before and after a wait with nothing sent. One so far, 2026-10-19:
  tmux 3.7c.
- **`tmux-<version>-progress-forwarding.json`** — what tmux passes on to the
  terminal it is drawn in (`progress_probe.py --tmux-forwarding`): the probe
  plays that terminal, as a client with the `progressbar` feature and as one
  without, and records the progress reports, notifications (`OSC 9`) and bells
  that reached it from a pane sending each (a report twice running among
  them), and the features tmux lists for it (`#{client_termfeatures}`); and,
  under `late_attach`, what a client with the feature is handed when it
  attaches to a pane that put a bar up before it. tmux 3.7c, 2026-10-19.
- **`tmux-3.7b-tonebases.json`** — the full Emoji_Modifier_Base sweep
  (`advance_probe.py --modifier-bases`): which of the 134 bases tmux merges
  with a following tone (70) and which it detaches (64). The source of
  `Character.tmuxMergedToneBases`, pinned row-for-row by
  `TmuxCompatibilityTests`.

## When a record is superseded — retire it, or keep it?

Both happen, and the reason is not "how old is it".

**An advance record for a superseded version stays.** `warpterminal-v0.2026.07.08.17.54-alternate.json`
is referenced by no test and describes a build nobody has installed, and it
stays anyway: it is the baseline the compatibility document's zero-drift claim
rests on. "The 2026-08-26 self-update reproduced every one of the 63 committed
rows exactly" is only checkable while both files are here. Delete it and that
sentence becomes something the reader has to take on trust, which is the
opposite of what this directory is for.

**A record the instrument got wrong goes.** The July *landing* record was
retired on 2026-08-28, when the probe was found to have been screenshotting
its own cursor inside the ink window (see the compatibility document's
"Measuring paint"). Its `ink` column contains values no terminal ever
produced, it cannot be re-measured — that build is gone — and a wrong number
with a provenance stamp is more dangerous than no number at all, because the
stamp is what makes it look trustworthy.

So the test is **is it wrong, or merely old**. Old is evidence. Wrong is a
trap, and the fact that it was written by a probe rather than by hand is
exactly why somebody would believe it.

**A re-run of the same version that reproduced every row replaced its
record.** Ghostty 1.3.1's two advance records were rewritten on 2026-10-19 by a
re-run on the same screens with mode 2027 set, as before: every row the old
records held came back the same (`pua_bmp_sf` under its corrected name,
`pua16_second`), and the battery had grown by fifteen rows on the primary
screen and eighty-two on the alternate. Nothing was lost — every number the old
files held is in the new ones, and the old files are in the history. A re-run
that differed, iTerm2 3.7.4's of 2026-10-13, was kept out of this directory
instead until its cause is known (the survey's "The drop-operation badge").

## Why the conditions are in the file

Twice now a measurement in this project has been recorded without the
precondition that made it valid, and both times the conclusion drawn from it
was wrong for a year:

- **Screen buffer.** iTerm2 and Warp advance some clusters differently on the
  primary and alternate screens. An early iTerm2 model was built from
  primary-screen readings and declared the host free of a quirk it has; the
  demo's closing brackets promptly painted into the glyphs.
- **DEC mode 2027.** Every Ghostty number was taken with grapheme clustering
  on — its default, so never wrong, but never checked. Resetting the mode moves
  six of eleven measured classes, and it persists across processes, so a probe
  can land in the other regime without anyone noticing.

So `stamp.screen` and `stamp.mode_2027_grapheme_clustering` are recorded on
every run, along with the date, OS, terminal version and the environment that
named the host. A record missing them is not a weaker record; it is an
uninterpretable one.

## What these numbers are, and are not

`advances` are **DSR cursor reports** — what the terminal *says* it did, and
that is ONE of a row's four facts. On Apple Terminal a ZWJ sequence reports
an advance of 5, 8 or 11 while the glyph composes into two cells — and an
earlier version of this note concluded from the paint that "the row does not
shear at all", which is FALSE: the advance governs wrapping, and a full-width
row budgeted at the painted 2 wraps (measured 2026-08-26). The paint governs
followers, the store governs later absolute writes, the reserve governs the
edge. An advance here that disagrees with TUIkit's width claim is a
hypothesis about rendering; confirm it with the wrap test plus
`landing_probe.py`/`treatment_card.py` — `visual_card.py` answers paint
only — before compensating. The project has reached a wrong conclusion from
a single fact in both directions.

## Adding a terminal

Run the probe, do not write the file:

```sh
cd Tools/TerminalProbes
PROBE_ALT=1 PROBE_OUT=data/<terminal>-<version>-alternate.json python3 advance_probe.py
```

`PROBE_ALT=1` measures the alternate screen, which is where TUIkit apps run and
what every model here is built from. A primary-screen record is welcome
alongside it — the difference between the two is itself a finding — but it is
not what the models use.

A new terminal's numbers are worth having even with no model written for it:
they are what a model would be built from, and until one exists the terminal
stays unidentified and its output is left alone, which is the correct
behaviour rather than a gap.

An advance record alone does not feed the conformance suite — that reads the
LANDING records. The full pipeline for a terminal that is getting a model:

```sh
cd Tools/TerminalProbes
PROBE_OUT=/tmp/landing.json PROBE_SHOT=/tmp/shot python3 landing_probe.py --wrap
python3 landing_analyze.py /tmp/landing.json \
    -o data/<terminal>-<version>-alternate-landing.json
```

then write the model from the record, and let
`TerminalLedgerConformanceTests` hold the two together.
