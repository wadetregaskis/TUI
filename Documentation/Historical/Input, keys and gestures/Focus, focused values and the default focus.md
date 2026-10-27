# Focus, focused values and the default focus

*When a focused-value reader sees its publisher, what "when no other view has
focus" means, and the focused objects declined. Ids: B34, B34-FULLER, B35,
C9.*

## In short

A reader drawn ahead of its publisher catches up a frame later (kept: both
fixes cost every frame). A preferred default focus applies when no other view
has focus, read the way B35 records. `@FocusedObject` and its modifiers are
declined.

## The record

### B34. A focused-value reader drawn ahead of its publisher catches up a frame later

*`FocusedValue`, `FocusedBinding`, `View.focusedValue(_:_:)`,
`View.focusedSceneValue(_:_:)`*

SwiftUI's readers are mostly `Commands` and toolbar items, which are updated
outside the view graph. A terminal has neither, so TUI's readers are views,
and they usually sit beside the publisher — a detail pane next to a list, a
status line above it — and are drawn before it in the same walk.

**Shipped:** a read answers from this frame's publications where the publisher
has already posted, and from last frame's where it has not. Every table handed
to a reader during a render is kept, and the reading is repeated at the end of
the pass against the frame's final publications and focus; if it differs, the
run loop is asked for one more frame. So a reader shows a value that changed
this frame one frame late (about 17 ms at the default rate), and a value that
did not change at once. A value that cannot be compared — a closure, a
`Binding` — counts as unchanged while the same view publishes it, so a closure
rebuilt every render cannot keep the loop spinning; a `Binding` reads through
to its source wherever it is read, so it is never stale either.

Two smaller readings, both SwiftUI-silent:

- Of several scene values for one key with none on the focus's path, the
  first published in the tree wins.
- A reader on the page beneath a sheet (the dimmed backdrop) reads the live
  tree's publications; the backdrop's own publishers publish nothing, since
  they are a picture of the page.

**The fuller version** removes the late frame: a publisher-only walk before the
real one, or deferring the readers' subtrees to the end of the walk. The first
is a second walk of every page that uses the API (a measure-shaped walk that
renders nothing, which the memos would mostly serve); the second breaks the
one-pass layout. Neither seems worth it for a one-frame delay that only a
reader ahead of a changing publisher sees. **A/B owed:** a reader records an
unkeyed read, so every memo above it declines to store; on a page whose root
holds a reader that is the whole page. Publishers are replayed by the memo, so
they cost nothing on a served frame.

### B35. What "when no other view has focus" means for a preferred default

*`View.prefersDefaultFocus(_:in:)`, `View.focusScope(_:)`, `ResetFocusAction`,
`EnvironmentValues.resetFocus`*

SwiftUI's documentation says the preference "sets the initial focus preference
when no other view has focus", is "limited to the focusable ancestor that
matches the provided namespace", and that a reset reevaluates default focus
"when the currently-focused item is within the provided namespace". Its
examples are tvOS ones. Three readings were needed:

- **Who has focus.** TUI focuses the first control of a screen or a newly
  presented sheet by itself, mid-render. That choice is not counted as a view
  having the focus, so the preferred control takes it from there; a focus the
  user, an app's `@FocusState` write or a `.defaultFocus` put somewhere is
  left alone. While an unapplied scope or preference is on screen the
  automatic choice waits for the end of the pass, so the first control inside
  a scope does not flicker through the focus; one before the scope can (it has
  registered before the scope was seen).
- **Once.** The initial preference is applied on the frame it first appears,
  then spent until its scope leaves the screen — the rule `.defaultFocus`'s
  `.automatic` priority already follows here.
- **No scope.** A preference whose namespace has no `.focusScope` applies to
  the whole screen, and a reset in that namespace moves the focus from
  anywhere.

**The alternative readings** are each a line to change: count the automatic
choice as holding the focus (then a preference only ever acts on a reset), or
make a scope-less preference inert. Neither has an obvious use. Not probed on
a SwiftUI build: focus needs a key window, which an offscreen hosting view does
not have.

**Decided 2026-10-12: an explicit focus overrides the default focus, and the
automatic choice must not count as held.** The first holds today: a focus the
user, an `@FocusState` write, a pending request or `.defaultFocus` put
somewhere is left alone (`FocusScopeTests`, `initialFocus` and
`initialFocusInsideScope`). The second holds only on the render pass that
makes the choice: each pass clears the mark (`FocusScopeRegistry.beginPass`), so a
scope that appears on a later frame, while the focus is still the automatic
pick, does not take it (`doesNotSteal`). So "who has focus" above is true for
one pass only. **Lane owed, one commit** (shipped 2026-10-13, below): keep the mark across frames until a
real focus event (a user's move, a click, an app's write or `.defaultFocus`),
and end it on any input delivered to the automatically focused control, so
focus never moves from under someone typing; a new test for a scope that
appears while the focus is still the automatic pick.

**Shipped 2026-10-13 (BITEMS1):** the mark lasts across frames. It ends when
the focus moves off the chosen control by any path, when anything focuses
that control explicitly (a click on it), and when a key is offered to it —
taken or not, or taken by an `onKeyPress` on its way there — or a press or a
wheel over it is taken (`wheelEndsTheAutomaticChoice`). The first-control
fallback at the end of a pass is the manager's choice too, as is the
neighbour an untouched choice falls back to when it leaves, at a pass's end
or unregistered by the app (`unregisterKeepsTheChoiceAutomatic`); a
`.focusHandoff` target (the app named it) and a page's focus restored when a
sheet closes are not. Tests: `takesTheUntouchedAutomaticFocus` (a scope
three frames on takes it), `doesNotSteal` (Return pressed it first) and
`declinedKeyEndsTheAutomaticChoice` (a key the button ignores).

### C9. `@FocusedObject`, `focusedObject(_:)`, `focusedSceneObject(_:)`

*`FocusedObject` (and its `Wrapper`, `init()`, `wrappedValue`,
`projectedValue`), `View.focusedObject(_:)`, `View.focusedSceneObject(_:)`*

All three take an `ObservableObject`, the Combine-based family §2.3 of the
compatibility doc declines for the whole framework. The `@Observable` forms
SwiftUI offers beside them ship — `@FocusedValue(Model.self)`,
`.focusedValue(model)`, `.focusedSceneValue(model)` — so the map entries are
`differentShape`, naming those.
