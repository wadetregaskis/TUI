# TUI 1.0

TUI is SwiftUI's programming interface for the terminal. You write views, `@State`, `@Observable` models, stacks, lists,
tables, navigation, sheets, menus and animations, and TUI draws them with Swift and the terminal's own escape codes: no
ncurses, nothing to install. The same package runs on macOS, on Linux and in a web browser.

This is the first release of TUI. It began as [TUIkit](https://github.com/phranck/TUIkit) by Frank Gregor; the tags
before `v1.0.0` in the repository are TUIkit's. These notes are the highlights. Everything else, with what to change in
an app, is in the full changelog linked at the end.

## Is it for you?

The goal is "learn once, write anywhere", not "write once, run anywhere". A terminal is a grid of character cells in one
font, so sizes are whole cells (`.padding(1)`, not `.padding(20)`) and some of SwiftUI has no meaning there. Where TUI
cannot do what you ask, your code usually fails to compile rather than being quietly ignored. This is a complete app:

```swift
import TUI

@main
struct Counter: App {
    @State private var count = 0

    var body: some Scene {
        WindowGroup {
            VStack {
                Text("Count: \(count)")
                Button("Add") { count += 1 }
            }
        }
    }
}
```

If you know SwiftUI you can read the rest of this page as a list of what is already there. If you do not,
[New to SwiftUI](https://swift-tui.com/docs/documentation/tui/newtoswiftui) explains the ideas from the beginning, and
[Getting Started](https://swift-tui.com/docs/documentation/tui/gettingstarted) takes you from an empty folder to a
running app.

## What you get

**Controls and presentation.** Text fields, buttons, toggles, pop-up menus, radio buttons, steppers, sliders, gauges,
progress views, date pickers, `Form`, `List`, `Table` (sorting, reordering, sections), `OutlineGroup`, `TabView`,
`NavigationStack`, `NavigationSplitView`, `HSplitView` and `VSplitView`. Sheets, alerts, confirmation dialogs, popovers,
toasts and tooltips. A menu bar from a scene's `commands`, with TUI's own app, File, Edit, View, Window and Help
menus, and toolbars placed as in SwiftUI. Open and save panels that TUI draws itself (`fileImporter`, `fileExporter`),
and `DocumentGroup` for document apps; `swift run DocumentEditor` is a small text editor built on it.

**Keyboard first, mouse too.** Every control works from the keyboard, and the mouse (clicks, drags, the wheel, hover)
works wherever the terminal reports it. Text fields and `TextEditor` have selection, undo, find and clipboard support.
Drag and drop has a keyboard route as well as a mouse one.

**Layout, drawing and styling.** Stacks, grids, `ScrollView` with lazy stacks, `Layout`, `GeometryReader`, alignment
guides and anchors. Shapes, `Path`, `Canvas` with `GraphicsContext`, gradients, materials such as frosted glass, shadows
and blend modes, all drawn in cells or, where the terminal allows, in its own pixels. Six classic phosphor palettes and
recreations of the ten macOS Terminal.app profiles, switchable at runtime or replaced with your own. Control styles
change how buttons, toggles, sliders and progress bars look.

**Animation.** `withAnimation`, `.animation`, springs, custom curves and `CustomAnimation`, `matchedGeometryEffect`,
transitions, `PhaseAnimator`, and a zoom navigation transition. Reduce Motion is honoured, and can be set by the app,
the user's system or an environment variable.

**Images and terminal graphics.** `Image` loads PNG, JPEG, GIF and BMP files, from a path, a URL or your package's
resources. In Ghostty, iTerm2 and Warp it is drawn in real pixels through the Kitty graphics protocol, and in terminals
with Sixel through that; everywhere else (including Apple's Terminal and tmux) it is drawn as coloured text characters
that occupy the same cells. The text rendering has tone, dithering, palette and glyph-set controls.

**Terminal compatibility.** TUI works out what the terminal can do when the app starts, and compensates for the
differences it knows about in Apple's Terminal, iTerm2, Ghostty, Warp, GNOME Terminal, tmux and xterm.js. It reads
the Kitty keyboard protocol where it exists, uses OSC 52 and OSC 5522 for the clipboard, and can show a progress bar
on the terminal's tab and post desktop notifications. The measurements behind this are kept in the
[terminal compatibility survey](https://github.com/wadetregaskis/TUI/blob/main/Documentation/Terminals/Terminal%20compatibility%20survey.md),
and `\.terminalCapabilities` lets your app ask for itself.

**Accessibility.** A terminal has no accessibility tree, so VoiceOver and `accessibilityLabel` have no counterpart. The
display preferences do exist: `accessibilityReduceMotion`, `accessibilityReduceTransparency`,
`accessibilityDifferentiateWithoutColor` and `colorSchemeContrast` are read as in SwiftUI, TUI's own controls follow
them, and the user sets them with environment variables, the system setting or the View menu. What a person asks for so
that they can use the program at all cannot be overridden by the app. Right-to-left layout is not supported yet.

**Localization.** TUI's own words come in seven languages: English, German, French, Italian, Spanish, Simplified Chinese
and Japanese. You add your own strings with `Localizable.strings` or by registering translations, and the language
preference is saved per app.

**Testing.** The `TUITesting` product provides `TestApp`, which runs a view or a whole app through the real render
loop, focus system and input chain without a terminal: press keys, click, move a clock by hand and read the screen.
It works with Swift Testing and XCTest, on macOS and Linux. See
[Testing your app](https://swift-tui.com/docs/documentation/tui/testingyourapp).

**Performance.** A frame is drawn only when something asks for one, and a screen with nothing changing does no work. A
render cache hands back what a subtree drew last time when nothing about it has changed, and the output is written as
a difference from the previous frame. `List` and `Table` draw only the rows that show, so a long data set costs no more per key than a short one.
[Keeping your app fast](https://swift-tui.com/docs/documentation/tui/keepingyourappfast) covers measuring and what to do
about a slow screen.

**Small apps.** `TUI` is the umbrella product. If binary size matters, depend on only the module products you use
(`TUIApp`, `TUITables` and so on); see
[Choosing Products](https://swift-tui.com/docs/documentation/tui/choosingproducts) and
[Building and shipping an app](https://swift-tui.com/docs/documentation/tui/shippinganapp).

## Platforms and requirements

- **Swift 6.2 or later** (`swift-tools-version: 6.2`). CI builds with Swift 6.2, 6.3 and 6.4.
- **macOS 15 or later** (`.macOS(.v15)`), built with Xcode 26 or later. CI covers macOS 15 and 26 with Xcode 26, and
  macOS 27 with Xcode 27.
- **Linux**, with no platform declaration needed. CI runs the three released Swift versions in Ubuntu containers on x86_64,
  and 6.3 on arm64.
- **WebAssembly** (`wasm32-unknown-wasip1`): the Example app runs in a browser [demo](https://swift-tui.com/demo/), and your
  own app can be published the same way. It needs a swift.org toolchain (not Xcode's) of 6.3 or later, with the matching
  WebAssembly SDK. See
  [Running your app in a browser](https://swift-tui.com/docs/documentation/tui/runninginabrowser).
- **Windows is not supported yet.** The four lowest modules (`TUICore`, `TUIStyling`, `TUIView` and `TUIImage`) build
  there and CI keeps them building, but the console layer (raw mode, signals, input) is not ported, so an app does not run.

## What is not there

TUI does not try to be all of SwiftUI. Whatever has no meaning in a grid of character cells is left out, and it fails to
compile so you know:

- No `scaleEffect`, `rotationEffect` or `blur` (a material gives a frosted look instead), no `Font.system(size:)` (one font,
  with text styles that change weight rather than size), no `ShareLink`, `onOpenURL` or safe areas.
- No VoiceOver or accessibility traits, and no right-to-left layout yet.
- The `ObservableObject` family is not supported. Use `@Observable`. `@StateObject`, `@ObservedObject` and
  `@EnvironmentObject` do not compile; `ObservableObject` and `@Published` do compile on macOS but TUI does not watch
  them, so a model moved over from SwiftUI that does not redraw is the first thing to check.
- Windows, as above.

Where code that compiles against both behaves differently on purpose, the difference is written down in
[Deliberate deviations from SwiftUI](https://github.com/wadetregaskis/TUI/blob/main/Documentation/SwiftUI%20parity/Deliberate%20deviations%20from%20SwiftUI.md),
and the ones most likely to matter are in
[Coming from SwiftUI](https://swift-tui.com/docs/documentation/tui/comingfromswiftui). A frame with a fixed size, for
example, aligns its content to the top left, where SwiftUI centres it.

## Where to start

- [Getting Started](https://swift-tui.com/docs/documentation/tui/gettingstarted): your first app.
- [New to SwiftUI](https://swift-tui.com/docs/documentation/tui/newtoswiftui): the ideas behind the code.
- [Coming from SwiftUI](https://swift-tui.com/docs/documentation/tui/comingfromswiftui): what is different.
- Coming from another terminal framework:
  [Bubble Tea](https://swift-tui.com/docs/documentation/tui/comingfrombubbletea),
  [Ink](https://swift-tui.com/docs/documentation/tui/comingfromink),
  [Ratatui](https://swift-tui.com/docs/documentation/tui/comingfromratatui) and
  [Textual](https://swift-tui.com/docs/documentation/tui/comingfromtextual).
- [Terminal support](https://swift-tui.com/docs/documentation/tui/terminalsupport): what works in which terminal.
- `swift run Example` from a checkout runs the Example app, a tour of what TUI can do.
