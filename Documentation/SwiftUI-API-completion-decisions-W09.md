# Wave 9 (focus, presentation and search): decisions for review

*Written by the worktree that implemented Wave 9, to be folded into
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md).
Same three parts: **A** needs your decision, **B** shipped the safe option,
**C** declined without asking. SwiftUI's behaviour quoted here is from its own
doc comments in the SDK's symbol graph unless an entry says it was measured.*

---

## A. Needs your decision

### A-W09-1 Let the reader move a sheet between its detents, and reach the page behind it?

*`View.presentationDragIndicator(_:)`, `PresentationContentInteraction.resizes`,
`PresentationBackgroundInteraction.enabled`,
`PresentationBackgroundInteraction.enabled(upThrough:)`*

Four symbols that only mean something if a sheet can be resized by the person
using it, or left half-open while they work in the page behind it. Neither is
possible here today: a multi-detent sheet changes size only through its
`selection:` binding (there is no grabber to drag), and the page behind any
presentation is drawn as an inert, dimmed backdrop under a throwaway focus
manager. What shipped are the values that describe that:
`PresentationContentInteraction.automatic`/`.scrolls` and
`PresentationBackgroundInteraction.automatic`/`.disabled`, each modifier
returning the view unchanged. The four above are left out, so they fail to
compile. On macOS they are probably inert too (sheets are window-modal there,
and the drag indicator is an iOS affordance), but I could not measure that with
an offscreen hosting view.

**Options.**

1. **Leave them out.** Free; the status quo.
2. **A grabber, by keyboard and pointer.** A `▔▔▔` row on top of a
   multi-detent sheet when `presentationDragIndicator(.visible)` (or
   `.automatic` with more than one detent), dragged with the pointer or moved
   by a key pair (Ctrl-Up/Ctrl-Down, say) to the next detent, writing the
   `selection:` binding when there is one. `.resizes` then means the wheel
   over the sheet resizes it before scrolling it. About a day with tests; the
   key pair has to be checked against the terminals' own bindings
   (`Terminal-compatibility.md`).
3. **Option 2, plus a live page behind a sheet** for `.enabled(upThrough:)`:
   the page renders live rather than as a backdrop, the sheet stops grabbing
   input below the given detent, and Tab crosses between them. That changes
   the presentation model's central rule (a presentation owns the keyboard),
   so it is two to three days and needs its own design note.
4. **Follow O8** if you rule there that APIs inert on macOS ship as inert.

**Recommendation:** 1 for now; 2 if detented sheets turn up in real apps.

### A-W09-2 `presentationSizing(_:)`: what are `.form` and `.page` in cells?

*`PresentationSizing` (`.automatic`, `.fitted`, `.form`, `.page`,
`fitted(horizontal:vertical:)`, `sticky(horizontal:vertical:)`,
`proposedSize(for:context:)`), `AutomaticPresentationSizing`,
`FittedPresentationSizing`, `FormPresentationSizing`, `PagePresentationSizing`
(and their `proposedSize(for:context:)`), `PresentationSizingRoot`
(`sizeThatFits(_:)`), `PresentationSizingContext`, `View.presentationSizing(_:)`*

macOS 15 sizes a sheet by one of these: `.fitted` is the content's ideal size,
`.form` "appropriate for forms", `.page` "roughly the size of a page of paper",
and `.automatic` is `.form.fitted(horizontal: false, vertical: true)` there. A
custom sizing proposes a size from the content's (`PresentationSizingRoot`), and
`sticky` keeps the largest size seen in an axis.

A terminal sheet today is `.fitted` exactly: the content is the sheet, and
only a detent changes its height, by handing the height to the content's
outermost box (`sheetDetentHeight`).

**Options.**

1. **Leave them out** (the status quo): sizing code fails to compile.
2. **Ship the family.** `.fitted` is today's sheet; `.form` proposes
   `min(64, width)` columns (about macOS's 540-point form sheet), `.page`
   `min(96, width)` columns by the content area's height; `.automatic` follows
   macOS (form width, fitted height). A proposal reaches the sheet's box the
   way a detent does, which needs a width twin of `sheetDetentHeight`
   consumed by `Dialog`, `Panel`, `Card` and `.border()`; `sticky` keeps the
   largest size in the presenter's state. A day with tests; it is a drawing
   change for no sheet that does not ask.
3. **Option 2 with `.automatic` left at `.fitted`**, so no existing sheet
   changes width.

**Recommendation:** 3. The numbers in 2 are mine and are the part to veto.

### A-W09-3 Compact-size-class adaptation and `preferredCompactColumn`

*`PresentationAdaptation` (`.automatic`, `.none`, `.popover`, `.sheet`,
`.fullScreenCover`), `View.presentationCompactAdaptation(_:)`,
`View.presentationCompactAdaptation(horizontal:vertical:)`,
`NavigationSplitView.init(preferredCompactColumn:…)` (all four)*

All of these say what to do in a compact size class: present a popover as a
sheet, show which split view column on top once the split collapses into one.
macOS is never compact, so on a Mac they are inert; TUIkit's size classes are
`.regular` unless an app sets them, and nothing TUIkit draws reads them (B3) —
the split never collapses and a popover never adapts.

**Options.**

1. **Leave them out** until B3 is decided.
2. **Ship them inert**, as macOS has them — under O8's option (b), citing
   the size classes never being compact here.
3. **Make them real:** a popover or sheet adapts by `PresentationAdaptation`
   when the environment's size class is compact (`.automatic` adapting a
   popover to a sheet, as iOS does), and a split view collapses into a stack
   showing `preferredCompactColumn` in a compact horizontal class. The
   adaptation is small (the popover presenter delegates to the sheet or cover
   presenter); the collapse is not (a split that becomes a stack keeps its
   columns' state and focus sections) — two days together. It only matters if
   B3 makes a narrow terminal compact.

**Recommendation:** decide with B3 and O8: 2 if O8 is (b) and B3 stays
"regular", 3 if B3 makes narrow terminals compact.

### A-W09-4 `DismissBehavior` waits on O9

*`DismissBehavior`, `.interactive`, `.destructive`*

It qualifies `dismissWindow` (`withTransaction(\.dismissBehavior, .destructive)`
closes a window even with a sheet up on it). `dismissWindow` is in the window
family the map declines, which O9 of the refusal review reopens. If O9 goes
(b) — secondary scenes as covers stacked over the main one — `.destructive`
means closing such a cover with its own presentations still up, and
`.interactive` refusing to; under (a) or (c) the type has nothing to qualify
and joins the decline.

### A-W09-5 `matchedTransitionSource` waits on O4

*`View.matchedTransitionSource(id:in:)`,
`View.matchedTransitionSource(id:in:configuration:)`*

The source half of the `.zoom` navigation transition, which O4 (matched
geometry and zoom transitions) covers. `NavigationTransition` and `.automatic`
shipped (the stack's own transition); `.zoom` and these two follow O4.

### A-W09-6 `presentationCornerRadius(_:)` waits on O0/O15

*`View.presentationCornerRadius(_:)`*

A sheet's corner radius. A terminal's corners are box-drawing glyphs, so the
honest reading is a choice of corner — `0` square (`┌`), anything larger
rounded (`╭`), `nil` the appearance's — applied to the sheet's box. But the box
is drawn by the content (a `Dialog`, a `Panel`), not by the presenter, and what
a radius means in cells is the question O0 (shapes) and O15
(`ButtonBorderShape`) are already asking. It should be answered once, there.

### A-W09-7 `searchSelection(_:)` waits on A13

*`View.searchSelection(_:)`*

It binds the search field's `TextSelection`. That type, and whether TUIkit
draws its own selection at all, is A13 (text selection) in the main decisions
doc. Once `TextField` takes a selection binding, this is a few lines on the
searchable's field.


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

### B-W09-7 An inspector is a split view's trailing pane: always a column, and its width bounds are not enforced

*`View.inspector(isPresented:content:)`, `View.inspectorColumnWidth(_:)`,
`View.inspectorColumnWidth(min:ideal:max:)`*

**Shipped:** the inspector is the trailing pane of an `HSplitView` beside the
view — macOS's presentation in a regular size class — starting at the width
named on its content (in columns) or 30, with the split's divider: a focus
stop the arrow keys move and the pointer drags. The view keeps its identity and
state while the inspector comes and goes.

**What differs:**

- A compact horizontal size class does not turn the inspector into a sheet,
  as iOS does. Here the size class is only compact when an app sets it, and
  nothing TUIkit draws reads it yet (B3).
- `min` and `max` are accepted and not enforced: the divider moves the column
  from one cell to all but one. SwiftUI documents that a platform may use a
  different width than asked, so this is within the contract, but it is the
  weaker reading.
- There is no keyboard command to show or hide the inspector — SwiftUI's comes
  from `InspectorCommands`, and `Commands` are O13.

**The fuller version** gives `HSplitView`'s panes bounds — a per-pane minimum
and maximum the divider stops at, which a `.frame(minWidth:maxWidth:)` on a
pane could state for every split, not only inspectors — about half a day; and
the sheet adaptation follows whatever B3 decides about compact size classes.

### B-W09-8 Three drawings chosen without a measurement: critical severity, the dialog icon, the subtitle

*`DialogSeverity.critical`, `View.dialogIcon(_:)`, `View.navigationSubtitle(_:)`*

- **Critical severity** is macOS's large caution symbol. Shipped: the
  dialog's border and title in the palette's warning colour, unless the alert
  was given colours of its own. A `⚠` before the title would say it in a
  glyph too, but U+26A0 is drawn one or two cells wide depending on the
  terminal, so it wants a `Terminal-compatibility.md` measurement and the
  chrome-glyph fallback first (an hour with the probes).
- **The dialog icon** sits at the leading edge of the message: an SF Symbol as
  its glyph, a raster image fitted into 8×4 cells. macOS draws it above the
  title in the new alert style and beside it in the old; beside the message
  costs no extra rows.
- **The subtitle** follows the title on the navigation bar's one row, in the
  secondary colour and truncating first; macOS puts it under the window title.
  A second bar row would vary the bar's height, which the stack's layout
  forbids (`NavigationStack.barHeight`).

Each is a one-line change if you would rather the other drawing.

## C. Declined without asking

### C-W09-1 `@FocusedObject`, `focusedObject(_:)`, `focusedSceneObject(_:)`

*`FocusedObject` (and its `Wrapper`, `init()`, `wrappedValue`,
`projectedValue`), `View.focusedObject(_:)`, `View.focusedSceneObject(_:)`*

All three take an `ObservableObject`, the Combine-based family §2.3 of the
compatibility doc declines for the whole framework. The `@Observable` forms
SwiftUI offers beside them ship — `@FocusedValue(Model.self)`,
`.focusedValue(model)`, `.focusedSceneValue(model)` — so the map entries are
`differentShape`, naming those.
