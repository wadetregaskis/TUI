# Completing the SwiftUI API: decisions from lane SPA2

*Lane SPA2 implemented step A2 of the module-split plan
(`buildtime/split2/plan.md`, §4 rows K1–K6): six refactors inside today's one
TUI module that remove the references which would point upward — from the
substrate (Base) into a feature leaf or into the POSIX app layer — once the
code is split. Where that work reached a judgement call the plan's rows did not
settle, the safe option shipped and is written up here, in the format of
[`SwiftUI API completion decisions.md`](<../SwiftUI API completion decisions.md>):
A for the owner to decide, B for a basic form shipped with its fuller version
priced, C for a refusal recorded in `parity-map.json`. None of these changes
public API; all are internal shape. One public behaviour changed in K2 and
was put back in review round 1: an `OpenURLAction` an app makes itself defers
to the running app's opener again (B-SPA2-6).*

## B. Shipped the safe option

### B-SPA2-1. Which per-subtree objects get a slot is the map's, not the row's prose

*`FeatureObjectSlot` (K1)*

Row K1's prose lists "navigation coordinator, dialog suppression, search
dismissal and scope keys, list-row edit restrictions". Read per declaration,
the plan's map places five of the objects `detachedFromRuntime()` clears in
leaves — the navigation coordinator (Navigation), the dialog suppression
(Presentation), and the search dismissal, focus offer and scope bar (Search) —
and places `listRowEditRestrictions` and `dismissalGate` in Base.

**Shipped:** five slots, one per leaf-owned object; the two Base-placed
objects stay plain keys, cleared by name.

**The fuller version** is a slot for any object the step-0c re-map moves up
(say `listRowEditRestrictions` to Lists): one enum case, one key, and the
accessor's two lines — ten minutes each, and DetachedFromRuntimeTests already
fails if such an object stops being cleared.

### B-SPA2-2. Outside any context's services there is no clipboard

*`ClipboardAccess.unavailable` (K2)*

The environment's default clipboard, and a text handler's default argument,
used to run this machine's helpers itself (`ClipboardAccess.system`): a test
rendering a field with no context's services wrote the developer's pasteboard
wherever the test process looked local. With the helpers behind the app layer's
backend, the substrate's default cannot reach them.

**Shipped:** no clipboard — a copy reports `.unavailable`, a paste reads
nothing. Every render a context drives publishes that context's writer
(in memory for every context but the app's), so only a bare test environment or
a hand-made handler meets it, and tests that copy already hand their subtree a
clipboard of their own.

**The fuller version** is an in-memory clipboard as the default too. Its price
is the reason it did not ship: the default is a static value, so it is either
one store the whole process shares (a singleton, which parallel tests would
race over, as they raced over the pasteboard) or a new store per read (each
field its own, and a `PasteButton`, which reads the environment every render,
always empty).

### B-SPA2-3. A context's in-memory URL opener reports the URL opened

*`InMemoryURLOpener` (K2)*

A deferral to the system opener reaches the opener only where opening URLs is
on (`TerminalURLOpening.isEnabled`); in a headless run or a test with it on,
that is now the context's in-memory opener rather than a real browser.

**Shipped:** it keeps the URL and answers `true`, as an in-memory clipboard
answers a copy `.copied`: the URL went where that context's URLs go.

**The other answer** is `false`, and all it would change is what the
completion form, `openURL(url) { accepted in … }`, reports. A `Link` raises its
destination popover on every activation whatever `open` answers
(`Link.swift`: `open(destination)`, then `showing.wrappedValue = true`, "raised
whether or not `open` 'worked'"), so a link looks the same either way. Nothing
reaches this but a headless run or a test that turned opening on, and the
change is one line; `true` stays because the URL did go where that context's
URLs go.

### B-SPA2-4. FieldTextLayout carries the selection look and no requirements, and WordBoundary moves down by placement

*`FieldTextLayout`, `FieldSelectionStyle` (K5)*

Row K5: "A small field-text-layout protocol in Base that the TextInput renderer
adopts. WordBoundary (53 lines) and the selection colours move down." What the
screen's selection needs from field text today is one thing: the selection
colours.

**Shipped:** a protocol with no requirements whose extension implements the
colours once; the text inputs' renderer and `ScreenSelection` both adopt it, so
neither names the other. `WordBoundary.swift`, a whole self-contained file,
was not edited: the brief allows no file moves in this step, and the step-0c
re-map places the file in Base.

**The fuller version** gives the protocol requirements — the field's cell
widths, its scroll window, its word rule — so the substrate could lay out a
field's text through it. Nothing in the substrate calls them today, so they
would be dead requirements, and a witness-table call where a focused field's
row now calls a static function.

### B-SPA2-5. Windows arms in the two files the row names; TerminalHost.swift still names `pid_t`

*`ProcessAncestry`, `ClipboardLocality` (K6)*

Row K6 gives ClipboardLocality.swift and ProcessAncestry.swift Windows arms
like their WASI ones. TerminalHost.swift, also placed in Base, names `pid_t`
too: `TmuxClient.pid`, `owningApplicationPath(ofTmuxClient:)`,
`executablePath(ofProcess:)` and the six builders of tmux hook and unhook arguments.

**Shipped:** the two files the row names. On Windows the walk by process id is
not compiled, `ownCommandNames()` and `tmuxClients()` answer `nil`, and
`ClipboardLocality.isLocal()` answers `false`, so no `pid_t` appears in either
file's Windows signatures. Unverified on Windows: this machine has no Windows
toolchain; the macOS build and the Linux static and WebAssembly cross-compiles
check every other arm.

**The fuller version** gives TerminalHost.swift the same treatment — its tmux
client probe and hook arguments compiled only where `pid_t` exists, with
`nil`/empty Windows arms — so that `pid_t` no longer stands between Base and a
Windows build. About an hour; worth doing when Base becomes an advisory Windows
step (B3).

### B-SPA2-6. An action no environment handed an opener defers to the running app's

*`TerminalURLOpening.runLoopOpener` (K2, review round 1)*

K2 injects the URL opener per context, and an action gets it by being read
from an environment: the `openURL` getter attaches that environment's opener.
But SwiftUI's `OpenURLAction(handler:)` is public, and an app may make an
action itself and call it directly, from a button's action, a `Task` or a
`DispatchQueue.main` block, where no environment handed it anything. Before
K2 such an action, deferring with `.systemAction` while opening was on,
launched `open`/`xdg-open`. With only the per-context opener it launched
nothing and answered `false`. That is a silent no-op in a running app, and
SwiftUI's documentation puts no condition on it: `systemAction` "asks the
system to open the original URL" (sdoc; what SwiftUI does with a hand-made
action is unmeasured).

**Shipped:** the app's run loop publishes its context's opener for the length
of the run (`AppRunner.publishURLOpener()`, at startup beside the opening
gate, withdrawn when the run ends), and an action that carries no opener
defers to it. Nothing else publishes one, so a headless run, a snapshot and a
test still launch nothing, and an action read from an environment still uses
that context's opener first. It is process-wide, like the `isEnabled` gate it
sits beside, because the callers it serves are exactly the ones no context
reaches. The framework creates nothing for it: the value is the running
context's own opener. It is read only when a deferral reaches the opener,
never per frame.

**The alternatives:**
- A task-local bound around the run loop. It needs no process-wide value, but
  an action called from a `DispatchQueue.main` block (which `App.main()`'s
  documentation invites) or a detached task sees nothing, so the silent no-op
  comes back for them.
- Make this the only route and drop the per-context key
  (`EnvironmentValues.urlOpener`). That removes the root-environment entry
  whose cost K2's A/B is measuring, at the price of row K2's "headless runs and
  tests get an in-memory one" for URLs: a deferral there would answer `false`
  instead of reaching the context's in-memory opener (B-SPA2-3). It is worth
  the owner's look only if that A/B prices the entry above noise.

