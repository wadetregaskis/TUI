# Terminal Support

See what works in which terminal, test your own, and know what to do about tmux and ssh.

## Overview

Your app runs in any modern terminal, with the same code. Terminals don't all have the same abilities, so TUI works out what each can do when your app starts, and uses the best it can. Most of the time, you don't need to do anything.

This page is for when you want to know what your users will see.

## What differs between terminals

| Terminal | Mouse | Pictures in real pixels | Keyboard protocol | Colours |
|---|---|---|---|---|
| Ghostty | Yes | Yes | Yes | Millions |
| iTerm2 | Yes, see below | Yes | Yes | Millions |
| Warp | Yes | No, text characters | Yes | Millions |
| Apple's Terminal | Yes, see below | No, text characters | No | 256 |
| GNOME Terminal | Yes | No, text characters | No | Millions |
| tmux | Passed on | No, text characters | No | Millions |
| A web browser, through xterm.js | Yes | No, text characters | Yes | Millions |

- **Mouse** means clicks, drags and the scroll wheel. Every control also works from the keyboard, so nothing depends on it.
- **Pictures** are drawn in real pixels where the terminal has the Kitty graphics protocol, and as coloured text characters everywhere else. Either way, an ``Image`` takes up the same cells.
- **Keyboard protocol** is the Kitty keyboard protocol, a newer way for a terminal to report keys. With it, an app can tell Control-I from Tab and Control-Shift-Z from Control-Z, and hear a key being released. Without it, those keys arrive looking the same, so a shortcut on one of them may never fire.
- **Colours** that a terminal can't show are replaced by the nearest it can. Fine gradients show steps at 256 colours.

Two terminals keep some of the mouse for themselves:

- **iTerm2** opens its own menu on a right-click unless you change that in its Pointer settings. A ``View/contextMenu(menuItems:)`` also opens on a Control-click for this reason.
- **Apple's Terminal** scrolls its own history on Shift and the scroll wheel, so an app never sees it. Use a trackpad's sideways swipe to scroll sideways.

A terminal that isn't in the table will probably work well too. TUI asks each terminal at launch whether it has pictures and the keyboard protocol, so those two follow whatever it can do.

## Test your terminal

To see what your terminal can do, run the demo app from a checkout of TUI:

```
git clone https://github.com/wadetregaskis/TUI.git
cd TUI
swift run Example
```

Then go through these in the demo, or in your own app:

1. Click a button and turn the scroll wheel over a list. If nothing happens, see Troubleshooting.
2. Open a page with a picture. A smooth photo means real pixels. Visible blocks of colour mean text characters.
3. Press Option-Left in a text field. If the caret doesn't jump a word, see "Option keys" below.
4. Check that borders line up and emoji don't push the text after them out of place.

`swift run TerminalClientQuirks`, also in the checkout, shows which terminal TUI thinks it's in, and how it worked that out.

Your app can ask the same questions at runtime, through ``EnvironmentValues/terminalCapabilities``:

```swift
struct PictureNote: View {
    @Environment(\.terminalCapabilities) private var terminal

    var body: some View {
        if terminal.status(of: .pictures) == .unsupported {
            Text("Pictures are drawn in text characters here.")
        }
    }
}
```

A feature can be supported, unsupported or undetermined. Undetermined means that nobody has found out yet, so don't tell someone their terminal can't do it.

## Option keys

Most Mac terminals type a special character when you press Option with a letter, unless you tell them not to. So Option-Left, Option-Backspace and the other Option shortcuts that text controls use can need a setting in the terminal:

- **Apple's Terminal:** turn on **Use Option as Meta Key** in Settings → Profiles → Keyboard.
- **iTerm2:** set the Option key to **Esc+** in the profile's Keys settings.

If your app has shortcuts of its own, prefer Control, which reaches the app in every terminal.

## tmux

TUI works under tmux with no settings. It recognises tmux and draws correctly for it. A few things differ from running directly in the terminal:

- **Mouse:** clicks, drags and the wheel reach the app, with tmux's `mouse` option on or off. If they don't, see Troubleshooting.
- **Pictures:** they're always drawn in text characters, because tmux doesn't pass real pixels on.
- **Image sizes:** tmux doesn't say how big a cell is, so an image that isn't `.resizable()` fits the space it's offered, rather than taking its natural size. Write `.resizable().scaledToFit()` and give it a frame to look the same everywhere.
- **Keyboard protocol:** it's off, so the keys it would tell apart arrive looking the same.
- **Clipboard:** for a copy to reach your computer's clipboard, add `set -g set-clipboard on` to your `tmux.conf`. At tmux's default setting, the terminal's clipboard isn't written.

## ssh

Over ssh, your app runs on the remote machine and draws in the terminal in front of you. Most things work as they do locally, but remember which machine is which:

- **Files:** ``View/fileImporter(isPresented:allowedContentTypes:onCompletion:)`` and its relatives browse the remote machine.
- **Clipboard:** a copy reaches your computer's clipboard only if your terminal accepts it through the terminal connection. When it can't, the status bar says so.
- **Colours:** ssh passes on `TERM` but not `COLORTERM`, so an app may use fewer colours than your terminal has. If colours look coarse, set `COLORTERM=truecolor` on the remote machine.
- **Which terminal it is:** ssh doesn't pass on `TERM_PROGRAM` either. TUI asks the terminal instead, which identifies the terminals in the table above. If emoji or borders still look out of line, name it yourself: `TUI_TERM_PROGRAM=ghostty`.

## Advanced: overriding what TUI decides

These environment variables settle a question without asking the terminal. Set them when running the app, or in a shell profile. They're mostly useful for checking how your app looks somewhere else.

| Variable | Effect |
|---|---|
| `TUI_GRAPHICS=0` or `1` | Pictures in text characters, or in real pixels |
| `TUI_KEYBOARD_PROTOCOL=0` | Doesn't use the keyboard protocol |
| `TUI_HYPERLINKS=0` or `1` | Links the terminal can follow, off or on |
| `TUI_TERM_PROGRAM=name` | Says which terminal this is: `Apple_Terminal`, `iTerm.app`, `ghostty`, `WarpTerminal`, `tmux` or `gnome-terminal` |
| `COLORTERM=truecolor` | Uses millions of colours |
| `TERM=xterm-256color` | Uses 256 colours, if `COLORTERM` isn't set |

To turn off real pixels for part of an app, because a blocky look is part of the design, write `.terminalGraphics(false)` around those views.

## See Also

- <doc:MouseAndGestures>
- <doc:KeyboardShortcuts>
- ``TerminalCapabilities``
- ``ColorDepth``
