# Keys from another device, and the keys F1 lists

*How a key that does not come from the terminal gets into the input chain, and
how an `onKeyPress` handler's keys get into F1's list. Ids: A-POSTKEY-1.*

## In short

An app posts a key with `@Environment(\.postKeyEvent)`, and it goes down the
whole input chain as a typed key does, its phase as posted, once the frame
being drawn is on the screen (A-POSTKEY-1).

## The problem

tuiarcade (its `TUI-FEEDBACK.md`, Milestone 3) turns a gamepad's buttons into
the keys they stand for, so each goes where the key goes. A running app had no
public way in: `FocusManager.dispatchKeyEvent(_:)` is one layer of the chain,
the focus system's, and reaches no `onKeyPress` handler, status-bar item or
shortcut (documented as such on 2026-11-20, `87947fce5`), and only a test's
`TestApp.press(_:)` delivered a key as the terminal does. So the arcade kept a
second path beside the keys, and wrote every rule of the chain (which handler
is asked first, what a modal swallows) a second time.

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
