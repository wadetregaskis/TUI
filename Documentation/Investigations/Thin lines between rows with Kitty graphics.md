# Thin lines between rows with Kitty graphics

> **Status:** open. Researched 2026-10-08, and the probe that gates it run the same day by the owner on Ghostty and
> iTerm2; the prototype (about 5–6 days) waits to be scheduled, and the default for list separators (decisions
> A-D6L-2) waits on it. **Asked by:** the owner, 2026-10-04 (A47: Kitty-graphics thin lines are "a later project …
> keep in mind, not now"). **Working notes** (not in git): `KGP/research.md` (the design, revised after a review),
> `KGP/records/`; the probe's own records are committed (below).

## Question

Every separator TUIkit draws between rows costs a whole row: `.listRowSeparator(.visible)` puts its `─` rule on a
line of its own, which is why separators are off by default where macOS draws a hairline under every row. Could a
terminal that speaks the Kitty graphics protocol draw a line one or two pixels thick on the boundary between two
rows instead, at no cost in rows, and what would it take?

## Answer

- **Feasible, but only with Kitty's classic placements,** which TUIkit had never emitted. The Unicode placeholders
  `Image` uses cannot do it: a placeholder cell is the picture and holds no text, so the line would cost the row it
  is meant to save. A classic placement is drawn at the cursor, outside the cell grid, with a pixel offset.
- **Ship it as a look, not a layout:** a TUI-only `.hairline` separator style that never takes a row on any host,
  and draws nothing where the graphics handshake says no. SwiftUI's separator modifiers stay as they are; SwiftUI has
  no separator-style API, so this would be a TUIkit addition beside them. With it, A-D6L-2 could take SwiftUI's
  default (separators on) without halving every list.
- **Draw it at the writer, from the composited frame:** the list marks the next row's first cells with a private
  marker; the writer turns marker runs into placements and keeps a model of what the terminal holds. A sheet or menu
  over the list then hides the line without special cases, and a scroll clip cuts it. SGR 58 is not the marker: it
  is the code SwiftUI-style underline colours will need, and it would colour a link's underline on a marked row.
- **Per host,** from source reading and then the probe: kitty, Ghostty and Rio look clean; iTerm2 works with
  quirks; WezTerm deletes the line on `ESC[2K`, which starts every whole-line rewrite, so the layer must re-place it;
  Konsole hides `z<0` under painted cells and TUIkit cannot yet recognise Konsole.

## Key measurements

`Tools/TerminalProbes/hairline_probe.py` (`c25452779`), run interactively by the owner on macOS 15.8.1 (arm64), on
the alternate screen, every card answered: Ghostty 1.3.1 and iTerm2 3.7.3. A 2048 × 2 px strip, placed with
`C=1` at the run's first cell on the lower row, so that its top edge is the boundary. Records are committed in
`Tools/TerminalProbes/data/` and written up in the
[Terminal compatibility survey](<../Terminals/Terminal compatibility survey.md#a-line-on-a-row-boundary-kitty-classic-placements--measured-2026-10-08-ghostty-131-and-iterm2-373>)
(`963018543`, `ad855dcf8`).

| | Ghostty 1.3.1 | iTerm2 3.7.3 |
|---|---|---|
| a line on the boundary | yes | yes |
| the layer that shows on every fill | `z=+1`, over glyphs (`z=-1` does not show on every fill band); the host must be identified first | `z=-1`; `z=+1` per fill band unmeasured |
| crop to the run's width | open: the arithmetic unit (16n px) was judged "no" once | no unit found: leave the host out until one is |
| after clear or a screen switch | re-send the strip (one store per screen) | nothing needed (one store, kept) |
| cleanup | delete by id | delete by id; a line left behind shows on the primary screen |

On both, whole-line rewrites kept the line, delete-and-re-place worked, a strip with no placement left could be
placed again without re-sending, and the line held steady at 60 Hz, with and without synchronized output (mode
2026).

## Reasoning

- **Why the writer, not the list:** the line must follow the final composited frame. Drawing it from the list would
  re-implement clipping, overlays and scrolling, which the writer already gets from the frame's cells (the
  argument of §11 of [Terminal graphics protocols](<../Images and terminal graphics/Terminal graphics protocols.md>)).
- **The risks:** the line lives outside the cell grid, so a missed resize, resume, modal, replay or scroll leaves a
  ghost; the marker must survive every stage that rewrites cells; a marker-only change leaves the built row identical,
  so the layer must diff its own runs. Tests must cover each.
- **The price:** about 5–6 days for the prototype on `List`, 5½–7 with a Konsole identity (estimates). The same
  writer path is what `Image` needs to reach WezTerm, Konsole and Warp through classic placements.

## Links

Decisions [D6L](<../SwiftUI parity/Decisions/List and table stripes, surfaces, pinned headers and separators (D6L).md>)
(A-D6L-2, the separator default); the compatibility guide's list-separator entry in
[SwiftUI compatibility guide](<../SwiftUI parity/SwiftUI compatibility guide.md>).
