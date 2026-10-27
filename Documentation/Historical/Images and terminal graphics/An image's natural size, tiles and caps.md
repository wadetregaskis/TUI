# An image's natural size, tiles and caps

*What size an image that is not resizable takes, on which hosts that can be
known, and how tiles and cap insets follow it. Ids: B-D3M-2, B-D3M-3,
B42. The live notes on pictures in terminals are
[Terminal graphics protocols](<../../Images and terminal graphics/Terminal graphics protocols.md>);
how glass, fades and veils came to work over pictures is in
[Materials and glass](<../Shapes, effects and animation/Materials and glass.md>).*

## In short

An image that is not resizable takes its natural size where the terminal's
cell size in points is known — four hosts, Ghostty only locally — and its
cells elsewhere. Tiles repeat at that size and cap insets are in points
(built 2026-10-19, settled by the parity rule and the owner's B42 ruling that
sizes following the font are accepted).

## The record

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
terminal TUI cannot ask.

**Judgement calls in it:**

- **Ghostty off its own Mac is unknown**, not guessed at scale 2. A guess would
  draw every image twice or half its size on a 1× display or a Linux host.
- **Ghostty locally uses the MAIN display's scale.** A Ghostty window on an
  external display of another scale draws its images half or twice their
  natural size. Which display the window is on is not something TUI can
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

### B-D3M-3. Tiles and caps follow the natural size, and caps are in points

*`Image.resizable(capInsets:resizingMode:)`, `Image.ResizingMode.tile` (B42)*

**Shipped at first:** unchanged by the natural size: a tiled image repeated at
the scale the whole image fits its frame at, and cap insets were in the image's
pixels.

**SwiftUI's reading** tiles at the image's natural size and takes cap insets in
points. Now that a natural size exists on most hosts, both could follow: the
slices would be cut at the natural cell box where it is known (and the fitted
one elsewhere), the insets multiplied by the image's scale, and the image's
per-view conversion cache keyed on the natural box too. About two hours with
tests. Left at first because no app in the tree tiles an image, and a tile size
that changes with the terminal's font is a behaviour change worth seeing first.

**Built 2026-10-19** (settled by the parity rule and the B42 ruling, which
accepts sizes that follow the font): where a cell's size in points is known, a
sliced image is cut at its natural cell box and its insets scaled by its pixels
per point (`_ImageResizing.sliceBox`, set where the image is drawn, so the
conversion cache, which compares the resizing, is keyed on it); elsewhere as
before (`ImageResizingTests`).
