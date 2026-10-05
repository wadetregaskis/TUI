# Completing the SwiftUI API: decisions from lane D1K

*Lane D1K implemented the owner's decisions A4 (the kitty keyboard protocol),
B7 (key-press phases), B12 (button repeat by keyboard) and A1 (`UndoManager`).
Where that work reached a judgement call the decisions did not settle, the
safe option shipped and is written up here, in the format of
[`SwiftUI-API-completion-decisions.md`](SwiftUI-API-completion-decisions.md):
A for the owner to decide, B for a basic form shipped with its fuller version
priced, C for a refusal recorded in `parity-map.json`.*

## B. Shipped the safe option

### B-D1K-1. Under the kitty keyboard protocol a ⌘ chord is dropped, not delivered

*`EventModifiers.command`, `KeyPress.modifiers`; the protocol's Super, Hyper
and Meta bits*

A terminal's legacy encodings never deliver a ⌘ chord: the terminal keeps it
for itself or sends nothing. Under the kitty keyboard protocol, a ⌘ chord the
terminal does not claim reaches the app, as the Super bit (kitty and Ghostty
report ⌘ that way on macOS; documented, not measured).

**Shipped:** a chord on Super, Hyper or Meta that types no text is dropped,
as the legacy encodings drop it; it still updates the modifier state, so
`onModifierKeysChanged` sees `.command` while ⌘ is held. Delivered as the
bare key, ⌘K would have typed a `k` into a text field and fired every bare-`k`
binding, and nothing that matches a key knows to look for ⌘.

**The fuller version** delivers the chord with ``EventModifiers/command`` in
its modifiers: `onKeyPress` would see `[.command]` as SwiftUI does, and a
`KeyboardShortcut` written with `.command` could match the real ⌘ where the
terminal passes it, before (or instead of) `commandKey`'s stand-in. Every
consumer that matches a bare character would have to learn to refuse ⌘ — text
fields, type select, the status bar, the theme and appearance keys, the
Example's page keys — and the stand-in rule would need a precedence: does
`KeyboardShortcut("s")` fire on ⌘S, on Ctrl-S, or both? About a day, most of
it the audit of bare-key consumers, and a question for you on the precedence.

### B-D1K-2. A modifier-key alternate in a menu does not inherit the modified view's shortcut

*`View.modifierKeyAlternate(_:_:)`*

SwiftUI turns an alternate inside a menu into an alternate menu item and
gives it the modified view's keyboard shortcut with the alternate's modifiers
added: `Button("Save").keyboardShortcut("s").modifierKeyAlternate(.option) {
Button("Save All") }` makes Save All ⌥⌘S, live whether or not the menu is
open.

**Shipped:** the alternate replaces the modified view — a row in a menu
included — while its keys are held, and takes no shortcut of its own. An app
that wants ⌥⌘S for Save All writes `.keyboardShortcut("s", modifiers:
[.command, .option])` on it, which works on every terminal.

**The fuller version** registers the alternate's derived shortcut whether or
not it is drawn. The alternate's action is only reachable by rendering it, so
this means rendering the alternate on every frame into a throwaway buffer (or
a registration-only walk), reading the modified view's resolved shortcut out
of its environment, and registering the union. Half a day, and a small cost on
every frame that has an alternate.

### B-D1K-3. Ctrl-H, I, J, M and [ fall back to their legacy keys when nothing binds them

*`KeyboardShortcut.isDeliverableInTerminal`, `KeyboardReporting.disambiguatesKeys`*

The protocol delivers these five as themselves, which is what makes them
bindable. But nothing binds them by default, and on every legacy terminal they
are Backspace, Tab, Return and Escape — Ctrl-[ to leave, Ctrl-H to rub out.

**Shipped:** a chord nothing in the input chain takes goes round once more as
the key it would have been. A binding on it still wins.

**The alternative** is to leave an unbound chord inert, as most of them are
in SwiftUI on macOS (the text system does bind ⌃H to delete backward, as the
fallback does; ⌃[ and ⌃M are nothing there). That would be truer to SwiftUI
and would break muscle memory on exactly the terminals that got better; I
chose the fallback. Free either way.

### B-D1K-4. `TUIKIT_KEYBOARD_PROTOCOL=0` keeps TUIkit from asking for the kitty protocol

*`EnvironmentValues.keyboardReporting`*

Not asked for, and nothing to decide on its own, but a new user-facing switch,
so recorded. The protocol is negotiated with every terminal that answers the
query. A terminal that answers and then encodes keys in a way TUIkit misreads
would leave a user unable to type into any TUIkit app on it, so the user gets
the same way out the hyperlink and graphics switches give:
`TUIKIT_KEYBOARD_PROTOCOL=0`, and the terminal stays in its legacy encodings.

**The fuller version** is a programmatic override for an app, as
`TerminalClient.hyperlinkSupport` is for links. Not built: nothing yet says an
app needs one. A quarter of a day.
