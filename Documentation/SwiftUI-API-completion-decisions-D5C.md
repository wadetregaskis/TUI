# Completing the SwiftUI API: decisions from lane D5C

*Lane D5C implemented the owner's decision A28 — toolbars, and the window's
chrome made opt-in — on the design study's Design 2 with policy P2
([`SwiftUI-API-completion-design-A28-chrome.md`](SwiftUI-API-completion-design-A28-chrome.md),
§10 steps 0–6). Where that work reached a judgement call the owner's answers
did not settle, the safe option shipped and is written up here, in the format
of [`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md):
A for the owner to decide, B for a basic form shipped with its fuller version
priced, C for a refusal recorded in `parity-map.json`.*

## B. Shipped the safe option

### B-D5C-1. `windowToolbarStyle(_:)` also takes a style chosen at run time

*`Scene.windowToolbarStyle(_:)`*

SwiftUI's modifier is generic over the style, and an app picks one statically.
A scene's modifiers cannot be chosen with an `if` (`SceneBuilder` has no
`buildEither`), and a call with an `any WindowToolbarStyle` cannot open the
existential, because the result's opaque type would depend on it. So an app
that lets its user choose — the Example's Theme page — had no way to apply the
choice.

**Shipped:** a TUIkit addition beside SwiftUI's generic form,
`windowToolbarStyle(_ style: any WindowToolbarStyle) -> some Scene`, marked
`@_disfavoredOverload` so SwiftUI source (`.windowToolbarStyle(.unified)`, a
concrete style) still binds to the generic one. A style an app writes itself
(a conformance with no framework reading) is drawn as `.automatic`.

**The fuller version** is no addition at all: give `SceneBuilder` an
`if`/`else` (`buildEither` producing a conditional scene) so the choice is
written as SwiftUI cannot write it either — a TUIkit extension in a different
place. About half a day, and it would let every scene modifier be chosen at
run time, not only this one. Or drop the addition and have the Example choose
the style at launch only. Your call if the addition's name sharing bothers you.

### B-D5C-2. An oscillating bar is pinned for a second, then tried again

*`WindowChromeState.settle` — the oscillation guard of §11*

The study's rule: never release a bar in the frame after reserving it, and
pin the union when a bar flips back within a short window, reporting it.
Shipped as written, with one choice the study left open — how long a pin
holds. Pinned for good, a page that changed its chrome three times in a
quick burst for a legitimate reason (a user flicking between pages faster
than twelve frames) would keep an empty bar until it declared something
new.

**Shipped:** a pin holds for one second (`WindowChromeState.pinNanos`); the
frame at its end — asked for, so a still screen gets it — tries the page's
declaration again, and a real oscillation pins again (and reports again)
within four frames. A declaration of any third height unpins at once.

**The fuller version** tells a layout oscillation from an input-driven one —
pin for good when no input arrived between the flips — at the cost of
threading "an event was delivered since the last frame" into the chrome
state. About two hours. Worth it only if the once-a-second flicker of a
genuinely oscillating page (reported on the diagnostic channel every time)
turns out to matter.
