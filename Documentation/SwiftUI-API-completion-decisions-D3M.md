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

## A. Needs your decision

### A-D3M-1. What else reduce motion should hold still

*`EnvironmentValues.accessibilityReduceMotion` (B53)*

Reduce motion now exists (`TUIKIT_REDUCE_MOTION=1`, or `Scene.reduceMotion()`),
and transitions with motion fade instead, as you decided. Nothing else TUIkit
draws reads it, because the rest moves by rules you set:

- **The focus breath.** Your rule is that focus ALWAYS breathes (2026-09-28).
- **Spinners and indeterminate progress**, which are motion by nature.
- **The caret's blink.**
- **Animated scrolling and `withAnimation` in general.** SwiftUI leaves these
  alone under Reduce Motion — it swaps transitions and leaves the rest to the
  app — so this one is parity as it stands.

**Options:**

- **(a) Leave them** (shipped). Parity with SwiftUI, which only swaps
  transitions; an app that wants more reads `\.accessibilityReduceMotion`.
- **(b) Hold the breath still** at its bright peak, stop the caret blinking
  (a steady caret, as terminals' own "no blink" setting gives), and draw
  spinners and indeterminate bars still (a fixed glyph and a static track).
  An exception to the always-breathes rule, scoped to users who asked. About
  half a day: the breath, the caret and the indicators each read one clock,
  and each would read the flag beside it.
- **(c) (b) without the spinners**, which tell a user that something is
  still happening and have no still form that says so.

**Recommendation: (c).** The breath and the blink are decoration a user who
asked for less motion should not have to watch; a spinner is information.


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

### B-D3M-4. The doubled format-style statics stay, and three calls inside B50

*`TUIkitAppKit` (B50); `FormatStyle`/`DiscreteFormatStyle` `.offset(to:)`,
`.reference(to:)`, `.timer(…)`, `.stopwatch(…)`*

**Shipped:** the bridges to Apple's graphics types are the `TUIkitAppKit`
product, and nothing TUIkit is built from imports AppKit, so an app that
imports only TUIkit sees nothing of SwiftUICore
(`CompileCorpusTUIkitOnly.swift` proves it, and fails if AppKit is imported).

**Calls made along the way:**

- **`internal import AppKit` was not enough.** A two-module probe (Swift
  6.2.4, macOS 15) shows a SwiftPM library built without library evolution
  still makes its client load an internally imported module, and SwiftUICore's
  members with it. `@_implementationOnly` hides it but warns of instability in
  exactly this configuration, and library evolution needs unsafe flags a
  dependency cannot carry. So no module below the bridges may import AppKit at
  all — a test now guards that (`AppKitBridgeTests`).
- **TUIkitImage decodes through ImageIO instead of `NSImage`**, its one reason
  to import AppKit. It turns a picture by its EXIF orientation as `NSImage`
  did, and of a file holding several images (an icon's sizes, a
  multi-resolution TIFF) it decodes the largest within the app's pixel limit,
  where ImageIO's first is often an icon's smallest. Vector formats `NSImage` rasterised (PDF, EPS)
  are no longer read; no app in the tree used one. Rasterising PDF through Core Graphics
  (`CGPDFDocument`) would bring them back without AppKit: about an hour.
- **The `CGColor` and `CGImage` bridges moved too**, though Core Graphics does
  not import SwiftUICore: one module for "Apple's graphics types" reads better
  than a split by which framework happens to import which. Moving them back to
  TUIkit is a few lines if you would rather they need no extra import.
- **The doubled statics stay.** Re-measured with a three-module probe: with
  TUIkit free of AppKit, a single declaration on `FormatStyle` serves an app
  that imports TUIkit alone — `Date.now.formatted(.offset(to: d))` included —
  but is ambiguous in a `DiscreteFormatStyle` context for an app that also
  imports `TUIkitAppKit` (or AppKit). The pair works for both, so removing the
  `DiscreteFormatStyle` copies would trade a compile error for every app that
  bridges a colour.
