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
as the dialog icon is, and the emoji where it cannot. The picture machinery
exists; the work is a caution glyph rasterised at the cell size, a dialog
layout that makes room for it, and the snapshot and PTY tests. About a day.
You said this is a later project; it is recorded here so it is not lost.

### B-D3M-2. An image's natural size is known on four hosts, and Ghostty's only locally

*`Image` sizing (B42), `EnvironmentValues.imageCellPoints`,
`View.imageCellPoints(_:)`, `ImageFitTarget.naturalSize`*

**Shipped:** an image that is not resizable takes its natural size where the
cell's size in points is known: Apple Terminal and Warp (their pixels are
points), iTerm2 (one `CSI 14 t` at startup, which it answers in points), and
Ghostty when the app runs on the Mac the terminal is on (its pixels are device
pixels; divided by CoreGraphics' main display scale). Everywhere else — tmux,
ssh to Ghostty, every unmeasured terminal — it fits what it is offered, as all
images did before. `ImageFitTarget` gained `.naturalSize` as its default, so
`.imageFitTarget(.proposedSize)` is now the way to ask for the old fitting on
every terminal; `.imageCellPoints(_:)` lets an app state the cell for a
terminal TUIkit cannot ask.

**Judgement calls in it:**

- **Ghostty off its own Mac is unknown**, not guessed at scale 2. A guess would
  draw every image twice or half its size on a 1× display or a Linux host.
- **Ghostty locally uses the MAIN display's scale.** A Ghostty window on an
  external display of another scale draws its images half or twice their
  natural size. Which display the window is on is not something TUIkit can
  ask from inside the terminal today.
- **Unmeasured hosts keep fitting.** kitty, WezTerm, foot, Alacritty and the
  rest report pixels too, but in a unit nobody here has checked; each is a
  probe run (the cell-aspect probe plus a look at the display's scale) away
  from joining the list.
- **Larger than its space, an image is cut from its top-leading corner**, where
  SwiftUI's overflows its frame, centred, and the window cuts it. Every view's
  buffer here is cut to its space; centring the cut would need the frame's
  alignment to reach the image.

**The fuller version:** measure the other common hosts (an hour each with the
probes), and for Ghostty ask the display scale another way if one appears.

### B-D3M-3. Tiles and caps keep the fitted scale, and caps are in pixels

*`Image.resizable(capInsets:resizingMode:)`, `Image.ResizingMode.tile` (B42)*

**Shipped:** unchanged by the natural size: a tiled image repeats at the scale
the whole image fits its frame at, and cap insets are in the image's pixels.

**SwiftUI's reading** tiles at the image's natural size and takes cap insets in
points. Now that a natural size exists on most hosts, both could follow: the
slices would be cut at the natural cell box where it is known (and the fitted
one elsewhere), the insets multiplied by the image's scale, and the image's
per-view conversion cache keyed on the natural box too. About two hours with
tests. Left for now because no app in the tree tiles an image, and a tile size
that changes with the terminal's font is a behaviour change worth seeing first.
