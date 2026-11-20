# Running Your App on Windows

Build and run your app on Windows, in Windows Terminal or the classic console, and know what differs there.

## Overview

Windows is supported as macOS and Linux are: the same code builds with Swift 6.2, 6.3 and 6.4, on arm64 and x86_64,
and runs in Windows Terminal and in the classic Windows console (conhost). The whole of TUI works there, the menu bar,
mouse, pictures, the clipboard and the file panels included, and your app needs no `#if os(Windows)` for TUI's sake.

What differs is mostly the terminal's, as it is between Mac and Linux terminals: <doc:TerminalSupport> says what each
of the two Windows terminals can do. This page is about the rest.

## What You Need

- **A swift.org toolchain for Windows**, 6.2 or later, and the Visual Studio Build Tools its installer asks for:
  `winget install Swift.Toolchain`, or the installer from [swift.org](https://www.swift.org/install/windows/).
- **Developer Mode**, in Settings → System → For developers. SwiftPM checks out one of TUI's dependencies,
  `swift-docc-plugin`, with symbolic links in it, and Windows lets a program make one only in Developer Mode or as an
  administrator. Without it, resolving your package fails.
- **A fresh Windows Terminal after installing a toolchain.** Every tab and window of a Windows Terminal that was
  running has the `PATH` it started with, so a program built since stops at launch: "The code execution cannot
  proceed because `swift_StringProcessing.dll` was not found". Quit every window of it, then start it again.

Toolchains of different versions install side by side, each adding itself to your `PATH` and setting `SDKROOT`: the
first on the `PATH` is the one that builds, and `SDKROOT` names the last one installed, so set both for the one you
mean. With two installed, Swift 6.4's default build system stops before building ("platform 'windows' already
registered"). Its older build system still builds: give `--build-system native` to the subcommand, after its name
and before a product's (`swift build --build-system native`, `swift run --build-system native MyApp`, `swift test
--build-system native`), since `swift` itself doesn't take it and what follows the product goes to your program. Or
keep one toolchain installed.

## Shipping

`swift build -c release` leaves `.build\release\MyApp.exe`, with TUI's resource bundle, `TUI_TUIStrings.resources`,
beside it to copy as on Linux (<doc:ShippingAnApp>). The program also needs the Swift runtime's DLLs where Windows
looks for them, beside the `.exe` or on the `PATH`: a machine with the toolchain has them in
`%LOCALAPPDATA%\Programs\Swift\Runtimes\<version>\usr\bin`, and one without needs them shipped with the program, or
swift.org's runtime installed. A program started without them stops before it draws, naming the DLL it couldn't find.

## Keys

TUI reads keys in Windows Terminal through the kitty keyboard protocol, from Windows Terminal 1.25, so it tells
Control-I from Tab and hears every modifier, as in Ghostty. The classic console sends the older encodings, where those
keys look the same, as in Apple's Terminal.

Windows Terminal keeps some chords for its own default bindings, and your app never hears them: among them
Control-Comma (its settings), Control-Minus (its font size), Control-Shift-V (paste), Control-Shift-A, Control-Shift-F,
Control-Tab, Control-Shift-T, Control-Shift-W, Alt-Return (full screen) and Control-Shift with the arrows, Home, End,
Page Up and Page Down (scrolling). TUI doesn't name a key that won't arrive, in the menu bar, the status bar or F1's
list of shortcuts, and names the one that does: Settings… shows F2 there, and undo and redo Control-Z and
Control-Shift-Z. If a shortcut of your own is on one of these chords, give it a second key with
``View/keyboardShortcutFallback(_:)``, and that's the one shown. Someone can rebind any of them in Windows Terminal's
settings, which TUI can't see, so the chord stays bound.

Quitting works as everywhere, with one addition:

- **Control-Q** quits, and **Control-\\** asks first, as on every platform.
- **Control-Break** quits at once, even an app that has stopped responding, after putting the console back as it
  found it. It's what Control-\\ does for a hung app on macOS and Linux.
- **There's no suspending.** Windows has no job control, so Control-Z is only a key (undo, unless your app binds it
  otherwise), and nothing stops the app to give the shell its console.

## Mouse

Clicks, drags, the scroll wheel, the right and middle buttons, Alt with a click and Control with the wheel all reach
the app, in both terminals. Two things don't:

- **Shift with the mouse.** Neither terminal passes Shift on with a click or the wheel. In Windows Terminal a
  Shift-click selects text on the screen instead.
- **The pointer's shape.** Neither terminal lets an app change it, so ``View/pointerStyle(_:)`` and a text field's
  I-beam leave the pointer as it is.

## Clipboard, Links, Notifications

- **Copying** reaches the Windows clipboard directly when you're at the machine the app runs on, whatever its size,
  each line ending in CR LF there and in a line feed inside the app. Over ssh a copy reaches your clipboard only
  through the terminal, which takes up to 24,567 bytes of text, so a larger one is reported as not copied.
- **Links** (``Link``, `openURL`) open in the program Windows has for the link's scheme. A link drawn in the text is
  followed with Control-click in Windows Terminal; the classic console draws it as plain text.
- **Notifications** are drawn in the app, as toasts, in both terminals. One posted to the desktop as well isn't shown
  there: neither terminal posts notifications, and Windows has no tool TUI can post one with, as it does with
  `osascript` on macOS and `notify-send` on Linux.
- **Progress** from ``View/terminalProgress(_:)`` shows as a ring on Windows Terminal's tab and on its taskbar button.

## Where Things Are Kept

Settings saved with `@AppStorage` go to `%APPDATA%\<your app's name>`, and settings shared by every TUI program to
`%APPDATA%\TUI\defaults.json` (<doc:StateManagement>). `APPDATA` is set by Windows; <doc:EnvironmentVariables> lists
what changes either.

## Running Another Program

``EnvironmentValues/handOffTerminal`` runs a program in the app's own console, as on macOS and Linux, and gives the
console back to the app when it ends. While it runs, Control-C and Control-Break go to it, not to the app. Windows has
no signals, so how it ended is its exit code alone.

## Things to Know as a Developer

- **`AttributedString.runs` doesn't link on Windows** with Swift 6.3.3. Code that touches it, even
  `string.runs.count`, fails to link with an undefined `BigString.Index` symbol: a gap in the Foundation that ships
  with the toolchain, not in TUI.
  `Text` draws an `AttributedString` without it, so only your own use of `runs` is affected; walk the string's
  characters, or a range's attributes, instead.
- **A thread's stack is 1 MiB on Windows**, where macOS and Linux give the main thread 8. TUI draws every frame on a
  stack of its own of 8 MiB, so a deep view tree draws as it does elsewhere; very deep recursion in your own code,
  outside a view's `body`, has the smaller stack to work with.
- **Tests run with `swift test`**, as elsewhere. Swift Testing runs a `@MainActor` test on a worker thread there, not
  on the process's main thread.

## See Also

- <doc:TerminalSupport>
- <doc:KeyboardShortcuts>
- <doc:ScenesAndQuitting>
- <doc:ShippingAnApp>
