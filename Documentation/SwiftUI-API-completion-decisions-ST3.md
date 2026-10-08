# Completing the SwiftUI API: decisions from lane ST3

*Lane ST3 carried out three of the owner's earlier "suggested tasks": the
`StdinArrivalNotifierTests` flake under load, a single tap lost after a failed
double tap, and the Stress cold bench keeping every frame's render state. It
changed no public API. This file holds the judgement calls the work reached that
the request did not already settle, in the format of
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md):*

- **A-ST3-n — needs your decision.** Nothing has shipped for these.
- **B-ST3-n — shipped the safe option.** Says what the fuller version would be,
  and its price.
- **C-ST3-n — declined.** With the reason.

## B. Shipped the safe option

### B-ST3-1. `renderOnce` empties its focus manager without telling the focused control

*`ViewRenderer.render(_:atRow:column:)`, `FocusManager.clearWithoutNotifying()`*

A `renderOnce` snapshot used to keep its whole render alive for the life of the
process: what the walk registered held closures over its `RenderContext`, whose
environment holds the services those closures were kept in. The fix empties the
services once the frame is written, as `App.cleanup` does at quit. `App.cleanup`
empties the focus manager with `clear()`, which first tells the focused control
it lost the focus: that is where a focused field's edit is committed at quit.
In a snapshot it ran the control's code after the frame was on the terminal. A
`TextField` the snapshot had auto-focused reported `onEditingChanged(false)`.

**Shipped:** the snapshot's teardown runs no view's code, as before the fix
existed. It empties the focus manager without telling anyone, so a snapshot of a
`TextField` reports `onEditingChanged(true)`, from its auto-focus, and never
`false`. That matches the type's documented snapshot semantics: no teardown
pass, and no side effects on shared state. A test pins it
(`ViewRendererTests.snapshotTeardownIsSilent`).

**The alternatives, and their price.**

- **Tell the control** (what `clear()` does): the arrival and departure would
  balance. The price is user callbacks running after the frame is drawn, from a
  renderer that otherwise runs no view code once it has drawn. One line to
  change.
- **Send neither:** suppress the snapshot's focus *arrival* as well, so nothing
  is announced at all. This is the more consistent version. Its price is
  unmeasured: auto-focus also decides which control draws its focus indicator,
  so the arrival's notice would have to be separated from the focus itself in
  `FocusManager`'s auto-focus path, which every live frame runs.
