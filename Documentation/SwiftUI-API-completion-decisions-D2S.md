# Completing the SwiftUI API: decisions from lane D2S

*Lane D2S implemented the owner's decisions A8 (`ScrollAnchorRole.alignment`),
A9 (`scrollContentBackground`), A6 (scroll target behaviours) and A10
(`scrollClipDisabled`). This file holds the judgement calls the work reached that
the owner's decisions did not already settle, in the format of
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md):*

- **A-D2S-n — needs your decision.** Nothing has shipped for these.
- **B-D2S-n — shipped the safe option.** Says what the fuller version would be,
  and its price.
- **C-D2S-n — declined.** With the `parity-map.json` reason.

## B. Shipped the safe option

### B-D2S-1. The alignment role places content on the vertical axis only

*`ScrollAnchorRole.alignment` (A8)*

SwiftUI places content shorter than a scroll view by the anchor's `y` on a
vertical view and by its `x` on a horizontal one (measured on macOS 15: a
100-point item in a 300-point `ScrollView(.horizontal)` sits at `x` 200 under
`.trailing` for `.alignment`, at 100 under the unlabelled `.bottom`, whose `x`
is 0.5). The cross axis is always centred, whatever the anchor says.

What ships reads `y` on a view that scrolls vertically, which is what the
owner's option 1 described, and ignores `x`, as TUIkit already does for the
other two roles ("the anchor modes are defined over rows"). So
`ScrollView(.horizontal) { … }.defaultScrollAnchor(.trailing, for: .alignment)`
compiles and keeps narrow content at the leading edge — a documented
deviation, on the role's doc comment and in the compatibility doc.

**The fuller version:** slide a horizontal view's drawn viewport right by the
anchor's `x` of the room, as the vertical slide does. What makes it more than
the vertical case's hour is that a horizontal view lays content narrower than
its viewport out at the viewport's width (`contentExtents`), so its natural
width has to be carried out of the measure, and content that fills the width
it is given (a `.frame(maxWidth: .infinity)`) has no room to place; SwiftUI
lays it out at its ideal width instead. About half a day, with tests, and it
changes the drawing of every horizontal view under an unlabelled `.bottom` or
`.center` (they would centre). SwiftUI's two-axis view adds the room to an
already centred position (an item drawn past the view's bounds, measured), which
looks like a SwiftUI bug and would not be copied.
