# Visual effects rulings: decisions from lane VISUALS

*Lane VISUALS, 2026-10-24, building the owner's rulings of 2026-10-23 on six
visual questions in `Documentation/Open owner decisions.md`: A34 (option 2),
B61 (2, landing if the A/B is within a few percent), B95 (2), O5-FROSTED (b),
P5 (c) and WL-Q3 (b, measuring first). Each section says what shipped, what
was measured, and any judgement call the ruling did not settle.*

## A34. `BlurReplaceTransition` is its scale and a fade

*`BlurReplaceTransition` (`Configuration`, `.downUp`, `.upUp`,
`init(configuration:)`, `configuration`, `body(content:phase:)`),
`Transition.blurReplace`, `Transition.blurReplace(_:)`; ruling: option 2.*

**What SwiftUI does** (measured on macOS 15.8, macOS 26.2 SDK,
[`Tools/SwiftUIProbes/Transitions/tr4.swift`](<../../../../Tools/SwiftUIProbes/Transitions/tr4.swift>),
a 200×100 view under a 2 s linear animation): besides the blur, the view
scales about its centre between **0.9** and its full size and fades linearly
between 0 and 1. `.downUp` arrives from 180×90 and leaves to it; `.upUp`
arrives from 180×90 and leaves to 220×110. `properties.hasMotion` is `true`
(`Animation curves, springs and keyframes/p1.swift`).

**What TUIkit draws.** The blur is drawn as the fade: at a cell's resolution a
blurred view reads as a faded one, and the opacity compositor already
dissolves its colours toward what is behind it. The scale is the `.scale`
reveal (B54) from 0.9 of the view at its centre. So `.downUp` erases to
`.scale(scale: 0.9, anchor: .center).combined(with: .opacity)` both ways, and
`.upUp` to that on insertion and `.opacity` alone on removal: a reveal cannot
draw a view larger than its slot. Under reduce motion it is a fade, as every
transition with motion is.

**Option 3**, a cell blur, was not built. The follow-up answer in the owner
decisions file prices it and ties it to O5-FROSTED's neighbour sampling.
