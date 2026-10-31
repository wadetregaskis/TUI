# Troubleshooting

Find the problem you're seeing, and fix it.

## Overview

Each section below starts with what you'll see, then says what to do. They begin with the problems you're most likely to meet on your first day.

## I can't quit my app

**Control-C does nothing, and `q` types a letter or moves around a list.**

Press **Control-\\**. It ends the app, and your terminal goes back to normal. Your shell may print `Quit: 3`, which you can ignore.

Plain `q` is the built-in quit key, but a focused text field or list takes every letter first. Press Tab until a button has the keyboard, and `q` will quit.

Control-C is an ordinary key while a TUI app runs, and nothing uses it unless you ask. To give people a dependable way out, add a Quit button with a shortcut, or choose the quit key:

```swift
struct ContentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.statusBar) private var statusBar

    var body: some View {
        VStack {
            MainScreen()

            // Control-Q, wherever the keyboard is.
            Button("Quit") { dismiss() }
                .keyboardShortcut("q")
        }
        // Or make Control-C quit, as it does in most command-line tools.
        .onAppear { statusBar?.quitShortcut = .ctrlC }
    }
}
```

## Nothing appears, or the app seems to hang

**You see no output, or stray escape codes, and the app never exits. It might be running in an IDE's output pane, in CI, or with its output going to a pipe.**

A TUI app needs a real terminal for its keyboard and screen. Without one, it waits for keys that can't arrive, with no error message.

Run it from a terminal window with `swift run`. If it's stuck in the background, stop it with your IDE's stop button, or with `kill`.

## The build fails: "requires macos 10.13"

**`error: the executable 'MyApp' requires macos 10.13, but depends on the product 'TUI' which requires macos 14.0`**

Add the `platforms` line to your `Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MyApp",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/wadetregaskis/TUI.git", branch: "main"),
    ],
    targets: [
        .executableTarget(name: "MyApp", dependencies: ["TUI"]),
    ]
)
```

## The build fails: "product 'TUI' not found"

**`error: 'myapp': product 'TUI' required by package 'myapp' target 'MyApp' not found.`, and your package uses a local copy of TUI.**

SwiftPM names a package after its folder, so a copy of TUI in a folder called anything else doesn't match. The simplest fix is to rename the folder to `TUI`. Or say which package you mean:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MyApp",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "TUI", path: "../my-tui-fork"),
    ],
    targets: [
        .executableTarget(
            name: "MyApp",
            dependencies: [.product(name: "TUI", package: "TUI")]
        ),
    ]
)
```

## The build fails: "'main' attribute"

**`'main' attribute cannot be used in a module that contains top-level code`, or `'main' attribute can only apply to one type in a module`.**

Swift treats a file called `main.swift` as the app's entry point, so it can't be used alongside `@main`. Rename the file to something like `App.swift`.

The second message means that two types are marked `@main`. `swift package init` may already have made a file with one, so delete that file or merge it with yours.

## The first build seems stuck

**`swift run` sits at "Fetching" or "Compiling" for minutes.**

That's normal the first time. It downloads TUI and a dependency of its macros, then compiles them. Later builds only compile what you've changed.

## Everything is huge, or missing

**A view you copied from SwiftUI has vast gaps, is cut off, or has gone off the screen.**

Sizes in TUI are whole character cells, not points, and a typical terminal is about 80 cells wide and 24 tall. So a `.padding(20)` takes up most of the height of the screen. As a rule of thumb, divide widths by 8 and heights by 16:

```swift
// In SwiftUI
VStack(spacing: 8) {
    Text("Name").padding(20)
}
.frame(width: 300)

// In TUI
VStack(spacing: 1) {
    Text("Name").padding(1)
}
.frame(width: 40)
```

<doc:ComingFromSwiftUI> lists the other differences.

## A view doesn't update

**The state changes, but the screen doesn't, or changes only when you press a key.**

Check these in order:

- **Is the data a plain class, or an `ObservableObject`?** TUI watches only `@Observable` types. It redraws for other classes only by chance, when something else causes a redraw, such as the next key press. That includes `@Published`, which compiles on a Mac but doesn't make TUI redraw. Change the class:

  ```swift
  @Observable
  final class Model {
      var count = 0
  }

  struct Counter: View {
      @State private var model = Model()

      var body: some View {
          Button("Count: \(model.count)") { model.count += 1 }
      }
  }
  ```

- **Is the object made in the view without `@State`?** A view struct is made again whenever its parent redraws, so a plain `let model = Model()` starts afresh each time. Hold it in `@State`, or pass it in.
- **Did you copy a value into `@State`?** `@State var value: Int` in a child takes its first value from the parent and then ignores later ones, as in SwiftUI. Write `let value: Int` to follow the parent, or `@Binding var value: Int` to change it too.

## Colours look wrong

**The app is green, or its colours don't match your terminal, look coarse, or are missing.**

- **It's green and you didn't ask for that.** Green is the default palette. To use your terminal's own colours, write `.palette(LiveTerminalPalette())` on your root view. <doc:ThemingGuide> has the others.
- **Colours look coarse or banded.** Your terminal may have only 256 colours, as Apple's Terminal does. Over ssh, set `COLORTERM=truecolor` on the remote machine if your terminal has more.
- **Bold text is a different colour.** Some terminals brighten bold text, which you can usually turn off in their settings.
- **There's no colour at all.** Check that `TERM` isn't set to `dumb`.

## Images look like coloured text

**A picture is made of blocks or characters rather than pixels.**

That's how pictures are drawn in a terminal without the Kitty graphics protocol, including Apple's Terminal, Warp and tmux. To see real pixels, run your app directly in Ghostty or iTerm2. To make the text version look better or different, see <doc:WorkingWithImages>.

If you see a line of text starting with `Error:` in place of the picture, the image didn't load. Check the path, which is relative to the folder you ran the app from, unless you make it absolute.

## The mouse doesn't work under tmux

**Clicks and the scroll wheel do nothing inside tmux, or do something else, but work outside it.**

Clicks reach a TUI app through tmux whether its `mouse` option is on or off, so look for something in the way:

- **Copy mode.** If the pane shows a position like `[0/120]` in its top corner, tmux has the mouse and keyboard. Press `q` to leave.
- **Your own mouse bindings.** A binding on `MouseDown1Pane` in `tmux.conf` has to pass the click on with `send-keys -M`. Otherwise tmux keeps it. To check, start a clean server with no configuration, using `tmux -f /dev/null -L test`, and try your app there.
- **Your app.** Look for a `.mouseSupport(.disabled)` that you've written somewhere.

See <doc:TerminalSupport> for what else differs under tmux and ssh.

## My terminal is messed up after a crash

**After the app was killed, typing shows nothing, or mouse movements print strange text.**

TUI puts the terminal back when an app quits or crashes, but it can't when it's killed outright with `kill -9` or when a debugger stops it. Type `reset` and press Return, even if you can't see what you're typing.

## See Also

- <doc:GettingStarted>
- <doc:ComingFromSwiftUI>
- <doc:TerminalSupport>
