# Keys from another device, and the keys F1 lists

*How a key that does not come from the terminal gets into the input chain, and
how an `onKeyPress` handler's keys get into F1's list. Ids: A-POSTKEY-1, A-KEYHELP-1.*

## In short

An app posts a key with `@Environment(\.postKeyEvent)`, and it goes down the
whole input chain as a typed key does, its phase as posted, once the frame
being drawn is on the screen (A-POSTKEY-1). An `onKeyPress` on a key or a set
of keys takes a defaulted `label`, and a labelled one is listed in F1's list by
its keys while its view is on the screen (A-KEYHELP-1).

## The problem

tuiarcade (its `TUI-FEEDBACK.md`, Milestone 3) turns a gamepad's buttons into
the keys they stand for, so each goes where the key goes. A running app had no
public way in: `FocusManager.dispatchKeyEvent(_:)` is one layer of the chain,
the focus system's, and reaches no `onKeyPress` handler, status-bar item or
shortcut (documented as such on 2026-11-20, `87947fce5`), and only a test's
`TestApp.press(_:)` delivered a key as the terminal does. So the arcade kept a
second path beside the keys, and wrote every rule of the chain (which handler
is asked first, what a modal swallows) a second time.

Its item 1, from the same milestone: F1's list of the keys in force is built
from `.keyboardShortcut`s, status-bar items and TUI's own keys, and a game
reads its keys with `onKeyPress(phases: .all)`, which nothing can ask what it
answers to. So the list showed ⌃Q, F1, F2 and Tab, and none of the game's
keys, and an app with keys of its own had to take F1 and hide TUI's list.

## Where it stands

Built on 2026-11-20. Nothing is owed.

## For a future reader

- A posted key waits for the frame to be on the screen, so it has up to a
  frame of latency (about 17 ms at the default rate) over a key typed at the
  same instant. That is the price of never running the chain inside itself and
  of acting on the focus the person can see; if an app ever needs less, the
  place to look is delivering posted keys with the run loop's input instead of
  after the frame, which needs its own rule for a key posted from inside a
  handler.

- The `label` is a parameter added to SwiftUI's own `onKeyPress`
  initialisers, so it lives or dies with their signatures. If SwiftUI ever adds
  a parameter named `label` to one, or a new overload whose trailing closure
  could be read as this one's, the call becomes ambiguous; the compile corpus
  (`Tools/APIParity/compile_corpus.sh`) is what would notice.

## The record

### A-POSTKEY-1. A way to send a key through the whole input chain

*`EnvironmentValues.postKeyEvent`, `PostKeyEventAction`*

Put to the owner on 2026-11-20 after tuiarcade's item 6: (a) a public
environment action that posts a key event through the whole chain, as a typed
key goes, phases included; or leave the arcade's parallel path as the answer.

**Decided 2026-11-20: (a).** `@Environment(\.postKeyEvent)`, an action value
called as a function, like `\.openURL` and `\.dismiss`. TUI-specific (SwiftUI
has no way to post a key), named so it shadows nothing of SwiftUI's.

**Shipped 2026-11-20.** `PostKeyEventAction` is the environment's, read off
the app's `KeysAfterFrame`, the queue a menu bar's items already press their
keys through, as `RingBellAction` is read off the bell: one per app, nothing in
the action itself, and outside a running app it does nothing. Calling it posts
the key, which the run loop delivers once the frame being drawn is on the
screen, in the order posted, through `InputHandler.handle(_:)`, the whole
chain: the focus path's `onKeyPress` handlers, the focused control, the status
bar, the view handlers, the shortcuts, TUI's own keys, and the bell for a press
nothing takes. It is noted as the keyboard's input, as a typed key is, so a
menu it opens highlights a row, and sends the pointer's tooltip away; a menu
item's key, which goes through the same queue, is not noted, as before.

The re-entrancy rule: **queued, never nested.** A key posted from inside a key
handler, typed or posted, is owed to the next frame, because the run loop hands
over only what was owed before it began pressing. So a handler that turns one
key into another cannot run the chain from inside itself, and one that posts a
key every time it hears one posts one a frame rather than looping without
returning. Delivering at once outside a handler and queueing only inside one
was considered and not taken: two timings for one call, and a key posted from a
view's body or a `.task` mid-frame would have run the chain against a
half-drawn frame.

A phase is delivered as posted: a release reaches the handlers that ask for
`.up` whether or not the terminal reports releases, which is what lets a pad
hold a key where a legacy encoding cannot. Tests: `PostKeyEventTests`.

### A-KEYHELP-1. How F1's list learns the keys an `onKeyPress` reads

*`View.onKeyPress(_:label:action:)`, `View.onKeyPress(_:phases:label:action:)`,
`View.onKeyPress(keys:phases:label:action:)`*

Put to the owner on 2026-11-20 after tuiarcade's item 1, with options for how
a view says what its key handlers answer to: (a) a modifier of its own beside
the handler, the arcade's `.keyboardShortcutHelp("← →", "move")`; (b) a
defaulted label parameter on `onKeyPress` itself; (c) an API for adding
sections to the list.

**Decided 2026-11-20: (b).** A defaulted label parameter added to `onKeyPress`
itself, under CLAUDE.md's "Extending SwiftUI's API": SwiftUI's overloads keep
their names, order and types, the parameter is added and defaulted, and no
SwiftUI call changes or becomes ambiguous.

**Shipped 2026-11-20.** `label: Text? = nil`, just before `action:`, on the
three overloads that name their keys: `onKeyPress(_:label:action:)`,
`onKeyPress(_:phases:label:action:)` and `onKeyPress(keys:phases:label:action:)`.
A `Text`, as SwiftUI's `badge(_:)` takes an optional one, so `Text("Move")`
is looked up and `Text(verbatim:)` is not, with one parameter and no new
overload; a `LocalizedStringKey` with a `StringProtocol` twin, the status bar's
pair, would have doubled the overloads to get a bare literal. Before `action:`
so the trailing closure reads as it does today: the forward scan skips a
parameter that is not a function. The overloads on a set of characters and on
any key take none, since they name no key the list could show; a catch-all's
keys are listed by giving them a handler of their own.

A labelled handler registers its keys and its label's words, read in the
render's language, with the frame's shortcut registry
(`KeyboardShortcutRegistry.noteKeyPress(_:title:section:)`) beside its
focus-path handler, and again whenever a memo replays that registration. It
binds nothing. The list shows it while its view is on the screen and not
disabled, whether or not that view holds the focus, under the page's section,
after the page's shortcuts, by the rules a shortcut is listed by (a modal's own
while a modal holds the keyboard; a pane's, and the page's where it reaches).
The keys are spelled through `KeyboardShortcut`, so with the glyphs a shortcut
is spelled with, side by side in a shortcut list's order, in one row; a key an
earlier row names is left out of the row.

Type-check cost, measured the day it shipped (Xcode's compiler): a file of 40
`onKeyPress` calls in one modifier chain, 30 of them to the three
overloads, takes 3,108 constraint-solver scopes against a build without the
parameter and 3,168 with it (+60, two for each call to an overload that has it),
and its body type-checks in the same time within noise (10 paired runs on a
busy machine: minimum 54.8 ms and median 63.0 ms without, 56.1 ms and 66.0 ms
with). The compile corpus takes 78,081 scopes without and 78,093 with (+12, its
six such calls), and 1.32 s of function bodies either way (minimum of 5 paired
runs: 1,316 ms and 1,327 ms). No overload was added, so no call has more
candidates than before; the file passes the type-check guard
(`-solver-scope-threshold=2000`) both ways.

Tests: `KeyboardShortcutOverlayTests` (a labelled handler listed, an unlabelled
and a disabled one not), the compile corpus for SwiftUI's call sites.
