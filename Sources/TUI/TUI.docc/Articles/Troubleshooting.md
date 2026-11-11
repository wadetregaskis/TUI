# Troubleshooting

Find the problem you're seeing, and fix it.

## Overview

Each section below starts with what you'll see, then says what to do. They begin with the problems you're most likely to meet on your first day.

## I can't quit my app

Press **Control-Q**.

If nothing happens, your app has bound that key to something else, or a sheet or dialog is holding it. Press **Control-\\** and answer the question it asks, or press it twice. It ends the app and puts your terminal back, even if the app has stopped responding, though that takes about two seconds. Your shell may print `Quit: 3`, which you can ignore.

To choose another key, see <doc:KeyboardShortcuts#Quitting>.

## "standard output is not a terminal", or the app won't start

**The app prints one line like `MyApp: standard output is not a terminal` and exits. It might be running in an IDE's output pane, in CI, or with its output going to a pipe.**

A TUI app needs a real terminal for its keyboard and screen. Run it from a terminal window with `swift run`.

The app says `standard input is not a terminal, so this app cannot read keys.` instead when its output is a terminal but its input isn't, as when you pipe something into it (`cat file | swift run`) or a script runs it with its input redirected. Give it the terminal's input, and read the file in the app instead. The same goes for `TERM=dumb`, which some editors' shells set: set `TERM` to your terminal's type.

If running that way should do something useful, such as printing a report, see "Running Without a Terminal" in <doc:ScenesAndQuitting>.

## The build fails: "requires macos 10.13"

**`error: the executable 'MyApp' requires macos 10.13, but depends on the product 'TUI' which requires macos 15.0`**

Add the `platforms` line to your `Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MyApp",
    platforms: [.macOS(.v15)],
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
    platforms: [.macOS(.v15)],
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

That's normal the first time. It downloads TUI and swift-syntax, which TUI's optional macros use, then compiles the parts of TUI your app uses. swift-syntax is compiled only if you use the macros. Later builds only compile what you've changed.

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

## "⋯ nested too deeply to draw"

**Part of the page shows this line where a view should be, or the last row of the screen does.**

Your views are nested too deeply for the call stack. Measuring and drawing a view uses stack for every level it's nested, and the stack is a fixed size, so TUI stops descending where it would run out. It draws everything above that point and this line in place of what's below, rather than crash. A `VStack` inside a `VStack` runs out after roughly a thousand levels in a release build, sooner if each level is in an `AnyView` or a `ScrollView`, and a debug build has roughly half that. The limit follows the stack the app really has, so it isn't a fixed number.

Your app reports it once, with the view it stopped at, the first time it happens. The report goes to the file named by `TUI_DIAGNOSTICS_FILE`, or otherwise to stderr when the app quits. SwiftUI runs out at a similar depth, between 1,000 and 2,000 levels of `VStack`, but there the app crashes.

- **Does a view contain itself?** A view with no case that stops, such as a `body` that holds another of the same view, goes on until the stack runs out. Add a case that stops:

  ```swift
  struct Branch: View {
      let node: Node

      var body: some View {
          VStack(alignment: .leading) {
              Text(node.name)
              // Stops where a node has no children.
              ForEach(node.children) { Branch(node: $0) }
          }
      }
  }
  ```

- **Is the data really that deep?** Show it a few levels at a time. A `List` with `children:` lays its open rows out flat, so it can show a tree of any depth, and a `NavigationStack` can go into a tree one level per screen.

A page that's past the limit draws from scratch on every frame, with nothing kept from the frame before. Its views below the limit aren't drawn, and their `.onAppear` and `.onDisappear` run as they would for any view that leaves the screen, but their `@State` is kept. What's below comes back as it was when the page is shallower again.

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

## A view redraws more than it should

**You want to know why a `body` runs.** Call `Self._printChanges()` at the top of it, as in SwiftUI:

```swift
var body: some View {
    let _ = Self._printChanges()
    Text("\(count)")
}
```

Each time the body runs it writes one line: `Counter: _count changed.` names the `@State` written, `@self` means the
parent passed a different value, `@identity` means the view is new at its place, and `an @Observable property changed.`
means the body read an `@Observable` property that was written. `@self may have changed.` means the view holds something
TUI can't compare, such as a closure or a `Binding`. `unchanged.` means everything was compared and nothing moved: the
parent's body ran again and drew this view with the same value. stdout is the screen, so set
`TUI_DIAGNOSTICS_FILE=/tmp/changes.log` and `tail -f` that file from another terminal. Without it, the lines go to stderr, held
until the app quits. `_logChanges()` writes the same lines to the unified log on a Mac.

## Colours look wrong

**The app is green, or its colours don't match your terminal, look coarse, or are missing.**

- **It's green and you didn't ask for that.** Green is the default palette. To use your terminal's own colours, write `.palette(LiveTerminalPalette())` on your root view. <doc:ThemingGuide> has the others.
- **Colours look coarse or banded.** Your terminal may have only 256 colours, as Apple's Terminal does. Over ssh, set `COLORTERM=truecolor` on the remote machine if your terminal has more.
- **Bold text is a different colour.** Some terminals brighten bold text, which you can usually turn off in their settings.
- **There's no colour at all.** Check that `TERM` isn't set to `dumb`, and that `NO_COLOR` isn't set in your shell profile, nor `FORCE_COLOR` or `CLICOLOR` to `0`. <doc:EnvironmentVariables> has what each does.

## Images look like coloured text

**A picture is made of blocks or characters rather than pixels.**

That's how pictures are drawn in a terminal that can't show pixels, including Apple's Terminal and tmux. To see real pixels, run your app directly in Ghostty, iTerm2 or Warp (which shows whole pictures only), or another terminal <doc:TerminalSupport> lists. To make the text version look better or different, see <doc:WorkingWithImages>.

If you see a line of text starting with `Error:` in place of the picture, the image didn't load. Check the path, which is relative to the folder you ran the app from, unless you make it absolute.

## The mouse doesn't work under tmux

**Clicks and the scroll wheel do nothing inside tmux, or do something else, but work outside it.**

Clicks reach a TUI app through tmux whether its `mouse` option is on or off, so look for something in the way:

- **Copy mode.** If the pane shows a position like `[0/120]` in its top corner, tmux has the mouse and keyboard. Press `q` to leave.
- **Your own mouse bindings.** A binding on `MouseDown1Pane` in `tmux.conf` has to pass the click on with `send-keys -M`. Otherwise tmux keeps it. To check, start a clean server with no configuration, using `tmux -f /dev/null -L test`, and try your app there.
- **Your app.** Look for a `.mouseSupport(.disabled)` that you've written somewhere.

See <doc:TerminalSupport> for what else differs under tmux and ssh.

## Key symbols show as boxes

**The status bar, menus or the shortcut list show `?` or empty boxes where keys such as ⌃ and ⎋ should be.**

Your terminal's font has no glyphs for those symbols. Set `TUI_KEY_SYMBOLS=0` to have keys written by name, such as `Ctrl-Q` and `Esc`, or choose View ▸ Spell Out Keys in an app with a menu bar. An app can ask for the names itself with ``Scene/keyNotation(_:)``.

## A notification doesn't reach the desktop

**A toast shows in the app, but nothing appears among your system's notifications, or the terminal only beeps.**

A notification goes to the desktop only when the app asks for it, by posting with `desktop:` set to `.whenInactive` or `.always` (see <doc:Presentation>). Then the terminal posts it, if it can. If it can't, this machine posts it itself, with `osascript` on macOS or `notify-send` on Linux, but only where TUI can tell you're sitting at the machine the app runs on, so never over ssh. `TUI_SYSTEM_NOTIFICATIONS=1` turns that on where TUI can't tell, such as inside zellij or GNU screen. If each one is only a beep, `TUI_NOTIFICATIONS=0` is set.

## Arrow keys go to the wrong control

**Down moves the keyboard to a control that isn't the one below.**

Arrow keys that a control doesn't use itself move the keyboard in Tab order, to the next or previous control, not to the nearest one on screen. To try arrows that go by the screen, set `TUI_ARROW_FOCUS=geometric`, or turn on Arrows Follow Layout in the settings panel (F2) or the View menu. It's an experiment. <doc:FocusSystem> says how sections group controls.

## Too much moves on screen

**You want things to stop gliding, fading or breathing.**

Set `TUI_REDUCE_MOTION=1`, or turn on Reduce Motion in your system's settings, and things jump to where they're going. The control with the keyboard still breathes; `TUI_BREATHING=0` holds it still. In an app with a menu bar, the View menu has both, as Reduce Motion and Breathing Focus.

## Colour is the only cue

**You can't tell which control has the keyboard, or which is disabled, because the only difference is a colour.**

Set `TUI_DIFFERENTIATE_WITHOUT_COLOR=1`, turn on Differentiate Without Color in your system's settings or, in an app with a menu bar, in its View menu. TUI's own controls then show the keyboard in reverse video and a disabled control faint, and mark a table's selected rows with a dot. `TUI_INCREASE_CONTRAST=1` asks for more contrast as well. <doc:EnvironmentVariables> lists the other settings.

## My terminal is messed up after a crash

**After the app was killed, typing shows nothing, or mouse movements print strange text.**

TUI puts the terminal back when an app quits or crashes, but it can't when it's killed outright with `kill -9` or when a debugger stops it. Type `reset` and press Return, even if you can't see what you're typing.

## See Also

- <doc:GettingStarted>
- <doc:ComingFromSwiftUI>
- <doc:TerminalSupport>
- <doc:EnvironmentVariables>
