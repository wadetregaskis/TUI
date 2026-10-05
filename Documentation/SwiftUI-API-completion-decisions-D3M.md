# Completing the SwiftUI API: lane D3M's decisions for review

*A companion to [`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md),
written by the lane that implemented the owner's answers to B39–B53 (2026-10-04).
It holds only what that work raised that was not already decided: the same three
parts as the main file.*

- **A. Needs your decision.** Nothing has shipped for these.
- **B. Shipped the safe option.** A basic, honest form is in; each entry says
  what the fuller version would be, and what it would cost.
- **C. Declined without asking.** Recorded in `parity-map.json`, listed so they
  can be vetoed.

## B. Shipped the safe option

### B-D3M-1. A critical dialog's caution sign is the ⚠️ emoji, not a full-size icon

*`DialogSeverity.critical` (B41)*

**Shipped:** as you asked, a critical alert or confirmation dialog starts its
title with ⚠️ (U+26A0 U+FE0F), keeping the warning colour on its border and
title. It is a VS-16 pictograph, a measured row of `Terminal-compatibility.md`'s
advance table, so the writer's existing compensation squares the two hosts that
advance it one cell (Terminal.app, iTerm2); it is drawn on every host, not only
the `supportsEmojiChrome` allowlist.

**The fuller version** is macOS's own presentation: a large caution symbol,
drawn as a picture through the Kitty graphics protocol on the hosts where
`Image` already draws pictures, sized to four or five rows beside the message
as the dialog icon is, and the emoji where it cannot. The picture machinery exists (`Image` already draws through it); the
work is a caution glyph rasterised at the cell size, a dialog layout that makes
room for it, and the snapshot and PTY tests. About a day. You said this is a
later project; it is recorded here so it is not lost.
