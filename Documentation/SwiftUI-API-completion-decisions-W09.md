# Wave 9 (focus, presentation and search): decisions for review

*Written by the worktree that implemented Wave 9, to be folded into
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md).
Same three parts: **A** needs your decision, **B** shipped the safe option,
**C** declined without asking. SwiftUI's behaviour quoted here is from its own
doc comments in the SDK's symbol graph unless an entry says it was measured.*

---

## A. Needs your decision

## B. Shipped the safe option

### B-W09-1 A focused-value reader drawn ahead of its publisher catches up a frame later

*`FocusedValue`, `FocusedBinding`, `View.focusedValue(_:_:)`,
`View.focusedSceneValue(_:_:)`*

SwiftUI's readers are mostly `Commands` and toolbar items, which are updated
outside the view graph. A terminal has neither, so TUIkit's readers are views,
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

### B-W09-2 What "when no other view has focus" means for a preferred default

*`View.prefersDefaultFocus(_:in:)`, `View.focusScope(_:)`, `ResetFocusAction`,
`EnvironmentValues.resetFocus`*

SwiftUI's documentation says the preference "sets the initial focus preference
when no other view has focus", is "limited to the focusable ancestor that
matches the provided namespace", and that a reset reevaluates default focus
"when the currently-focused item is within the provided namespace". Its
examples are tvOS ones. Three readings were needed:

- **Who has focus.** TUIkit focuses the first control of a screen or a newly
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

### B-W09-3 Preventing termination stops the quit key, and "automatic" prevents nothing

*`View.presentationPreventsAppTermination(_:)`,
`View.dialogPreventsAppTermination(_:)`*

**Shipped:** `true` stops the quit key (`q` by default, or the app's
`quitShortcut`) and takes it off the status bar while the presentation is
drawn; `false` and `nil` leave it working. Several statements combine as
SwiftUI documents for the sheet form: a non-`nil` one overrides `nil`, and
`true` takes precedence over `false`. Signals are not stopped — Ctrl-C and
`kill` still end the app, which is what a force quit is on macOS and the only
way out of a terminal app that has stopped listening.

**What differs:** SwiftUI's `nil` is an automatic rule that usually prevents.
A sheet prevents unless its toolbar holds a single confirmation or
cancellation item; a dialog prevents unless it has one non-destructive button,
is not critical and holds no text field. TUIkit's `nil` keeps what it did
before this wave: the quit key works behind every presentation, as the
escape hatch its status bar offers.

**The fuller version** adopts macOS's automatic rule. The dialog half is a
few lines — the button roles are known (`alertActionButtons`), severity has
shipped, and alerts take no text fields yet. The sheet half has nothing to
read: a terminal sheet has no toolbar, so the rule would collapse to "a sheet
always prevents", which would take the quit key away behind every sheet in
every app. That is the decision: I would adopt the dialog rule and leave
sheets at "never".

### B-W09-4 A dismissal confirmation asks before the reader's ways out, not before `dismiss()`

*`View.dismissalConfirmationDialog(_:shouldPresent:actions:)`,
`View.dismissalConfirmationDialog(_:shouldPresent:actions:message:)`*

SwiftUI's doc says the dialog is presented "when a dismiss action has been
triggered", and on macOS "when attempting to dismiss the window for this
view".

**Shipped:** on a presentation's content, the presentation's own ways out ask
first — Escape, an outside click (a popover), the status-bar item; on an
app's top-level content, the quit key does, the terminal's nearest thing to
closing the window. Cancel keeps what was about to go; every other action runs
and then lets it go.

**What is not intercepted:** an app's own `@Environment(\.dismiss)` call. It
is a decision the app made in code, and its usual shape — a Save button that
saves and dismisses — would otherwise ask about the changes it has just saved
whenever `shouldPresent` lags a frame. Nor is a pushed `NavigationStack`
screen's Escape (back), or a signal.

**The fuller version** wraps `\.dismiss` for the content too. The catch is
cost, not code: `DismissAction` is not `Equatable`, so writing one into the
environment turns the memos off below it, and on a top-level content that is
the whole app. It wants `DismissAction` made comparable first (an
identity-compared box, as `searchable`'s dismissal is), which every presenter
writing one would gain from — half a day with the memo tests.

### B-W09-5 Search scopes show while the search is under way, by a terminal's reading of "presented" and "cancelled"

*`View.searchScopes(_:scopes:)`, `View.searchScopes(_:activation:_:)`,
`SearchScopeActivation`*

SwiftUI shows the scope bar "when SwiftUI presents search" (macOS) or "when
someone enters text" (iOS), and hides it "when someone cancels the search".
On macOS the search field lives in a toolbar and is presented by clicking it.
Here it is always on screen at the top of the searchable subtree.

**Shipped:** presented is the field holding the focus, as `isSearching` already
was; cancelled is `dismissSearch` (or `isPresented = false`), or leaving the
field with nothing typed. So under `.onSearchPresentation` and `.automatic`
(macOS's default) the scopes show while the field has the focus or the query
is not empty; under `.onTextEntry`, while the query is not empty. Under both
they stay while the focus is in them, or Tab from the field would hide the
picker it was heading for.

**The alternative** is to show the scopes whenever the field is on screen,
since a terminal's field is never hidden. That reads well for a dedicated
search page but makes `.onTextEntry` meaningless, so it would have to be a
TUIkit-only activation rather than a reading of SwiftUI's.

### B-W09-6 Suggested search tokens are a row of buttons, not entries in the suggestions menu

*`View.searchable(text:tokens:suggestedTokens:placement:prompt:token:)`,
`View.searchable(text:tokens:suggestedTokens:isPresented:placement:prompt:token:)`*

SwiftUI lists suggested tokens in the search field's suggestions, as it lists
`searchSuggestions`. TUIkit's suggestions are a drop-down of text completions
(`TextSuggestions`), opened by Down at the caret; an entry fills the field
with its text and has no notion of becoming a token.

**Shipped:** the suggested tokens are a row of buttons under the field, shown
while the field holds the focus with nothing typed (and while the focus is in
the row), on the same terms as the scopes; choosing one appends it to `tokens`,
and a token already chosen is not offered again. The tokens themselves draw in
the field as `[Apple] [Pear]`, in the accent colour, and Backspace in an empty
field removes the last.

**The fuller version** teaches the suggestions drop-down a second kind of entry,
one that appends a token instead of completing text, and offers the suggested
tokens there, above any `searchSuggestions`: the menu, its keyboard handling
and its Return-to-submit rule all live in one place (`TextInputSuggestions`),
so it is about half a day with tests.

## C. Declined without asking

### C-W09-1 `@FocusedObject`, `focusedObject(_:)`, `focusedSceneObject(_:)`

*`FocusedObject` (and its `Wrapper`, `init()`, `wrappedValue`,
`projectedValue`), `View.focusedObject(_:)`, `View.focusedSceneObject(_:)`*

All three take an `ObservableObject`, the Combine-based family §2.3 of the
compatibility doc declines for the whole framework. The `@Observable` forms
SwiftUI offers beside them ship — `@FocusedValue(Model.self)`,
`.focusedValue(model)`, `.focusedSceneValue(model)` — so the map entries are
`differentShape`, naming those.
