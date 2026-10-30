<h1 align="center">TUI</h1>

<p align="center"><strong>A Terminal UI framework for Swift, modelled after SwiftUI.</strong></p>

<p align="center">
    <img alt="Platforms" src="https://img.shields.io/badge/Platforms-macOS%20%7C%20Linux%20%7C%20WebAssembly-005c00">
    <img alt="Swift 6.2" src="https://img.shields.io/badge/Swift-6.2-00b300?logo=swift&logoColor=white">
    <img alt="i18n" src="https://img.shields.io/badge/i18n-7%20Languages-00d900">
    <img alt="License" src="https://img.shields.io/badge/License-MIT-00b300?style=flat">
    <a href="https://github.com/wadetregaskis/TUI/actions/workflows/ci.yml"><img alt="CI" src="https://img.shields.io/github/actions/workflow/status/wadetregaskis/TUI/ci.yml?branch=main&label=CI&color=009900"></a>
</p>

<p align="center">
    <img src="https://swift-tui.com/media/latest/mixer.webp" width="800" alt="A mixing desk made with TUI, in Ghostty: faders and pan knobs dragged with the mouse, and the level meters answering.">
</p>

Write SwiftUI, and get a terminal app. TUI speaks SwiftUI's language: views,
`@State`, stacks, lists, tables, navigation, sheets, menus and animation. It
draws them with nothing but Swift and the terminal's own escape codes: no
ncurses, nothing to install. It runs on macOS and Linux, and in a browser,
compiled to WebAssembly.

> [!IMPORTANT]
> TUI is a work in progress, ahead of its 1.0. Its APIs can change in any commit.

## A taste

```swift
import TUI

@main
struct Groceries: App {
    var body: some Scene {
        WindowGroup { ShoppingList() }
    }
}

struct ShoppingList: View {
    @State private var items = ["Apples", "Bread", "Coffee", "Dates", "Eggs", "Figs"]
    @State private var bought: Set<String> = []
    @State private var query = ""

    var body: some View {
        List(items.filter { query.isEmpty || $0.localizedStandardContains(query) }, id: \.self) { item in
            Toggle(item, isOn: Binding(
                get: { bought.contains(item) },
                set: { if $0 { bought.insert(item) } else { bought.remove(item) } }))
        }
        .searchable(text: $query)
        .navigationTitle("Groceries")
    }
}
```

If you know SwiftUI, you already know how this reads, and what it does.

## In a real terminal

Every clip below is a TUI app playing itself in a real terminal window,
filmed and looped. Nothing is mocked up.

<table>
<tr>
<td width="50%" valign="top">
<img src="https://swift-tui.com/media/latest/images.webp" width="400" alt="A picture viewer stepping through wildlife photographs, drawn as real pixels.">
<br><strong>Real pictures.</strong> Photographs drawn as pixels, through the Kitty graphics protocol, wherever the terminal speaks it.
</td>
<td width="50%" valign="top">
<img src="https://swift-tui.com/media/latest/glyphs.webp" width="400" alt="The same kind of picture drawn in text characters, its style changed in an inspector.">
<br><strong>…or text, everywhere else.</strong> Glyph sets, shape matching, palettes, dithering and tone curves, chosen by modifier.
</td>
</tr>
<tr>
<td valign="top">
<img src="https://swift-tui.com/media/latest/tables.webp" width="400" alt="An activity monitor's process table: scrolled, sorted by column, a row followed, filtered by name.">
<br><strong>Tables.</strong> Live data under a fixed header, sorted by a click on a column, followed, and filtered with <code>.searchable</code>.
</td>
<td valign="top">
<img src="https://swift-tui.com/media/latest/dragdrop.webp" width="400" alt="A task board whose cards are dragged between columns, three at once.">
<br><strong>Drag and drop.</strong> Between lists and within them, a whole selection at a time.
</td>
</tr>
<tr>
<td valign="top">
<img src="https://swift-tui.com/media/latest/materials.webp" width="400" alt="A photo album with a share panel and a toast on frosted glass over it.">
<br><strong>Materials.</strong> Frosted glass over the terminal's own pixels.
</td>
<td valign="top">
<img src="https://swift-tui.com/media/latest/animation.webp" width="400" alt="A card game: spells cast from a hand of cards, with a battle log.">
<br><strong>Animation.</strong> <code>withAnimation</code>, springs and transitions, at the terminal's frame rate.
</td>
</tr>
<tr>
<td valign="top">
<img src="https://swift-tui.com/media/latest/navigation.webp" width="400" alt="A field guide in a three-column split view; a photo zooms up into a screen of its own.">
<br><strong>Navigation.</strong> Split views with columns you can drag, and a photo that zooms into a screen of its own.
</td>
<td valign="top">
<img src="https://swift-tui.com/media/latest/document.webp" width="400" alt="A postcard app: a picture picked in an open panel, saved, exported as Markdown.">
<br><strong>Documents.</strong> Open and save panels, unsaved changes, export: a document's whole life.
</td>
</tr>
<tr>
<td valign="top">
<img src="https://swift-tui.com/media/latest/controls.webp" width="400" alt="An event planner filled in from the keyboard: fields, a pop-up, a stepper, a calendar.">
<br><strong>Controls.</strong> Fields, pop-ups, switches, steppers, gauges and a calendar, every one of them from the keyboard.
</td>
<td valign="top">
<img src="https://swift-tui.com/media/latest/styles.webp" width="400" alt="A train booking form whose controls change their look every two seconds.">
<br><strong>Styles.</strong> One form, five looks, a modifier each.
</td>
</tr>
<tr>
<td valign="top">
<img src="https://swift-tui.com/media/latest/theming.webp" width="400" alt="A build window whose colours and borders change while it runs.">
<br><strong>Themes.</strong> Palettes and borders, changed while the app runs.
</td>
<td valign="top">
<img src="https://swift-tui.com/media/latest/tracks.webp" width="400" alt="A backup's progress bar, restyled as it fills, and a bandwidth slider.">
<br><strong>Progress and sliders</strong> in more styles than you will need.
</td>
</tr>
<tr>
<td valign="top">
<img src="https://swift-tui.com/media/latest/menus.webp" width="400" alt="A mail client's menu bar and context menu in Apple's Terminal.">
<br><strong>Menus.</strong> A menu bar, context menus and keyboard shortcuts, here in Apple's Terminal.
</td>
<td valign="top">
<img src="https://swift-tui.com/media/latest/textedit.webp" width="400" alt="A notes editor in Warp: text selected with the mouse, dragged to a new place, edited.">
<br><strong>Text editing.</strong> Select with the mouse, drag to move, jump by word, undo. Here in Warp.
</td>
</tr>
<tr>
<td valign="top">
<img src="https://swift-tui.com/media/latest/unicode.webp" width="400" alt="One screen of languages and scripts in Ghostty, iTerm2, Apple's Terminal and Warp.">
<br><strong>Every terminal.</strong> One screen in four terminals, each drawn the way that terminal draws text.
</td>
<td valign="top">
<img src="https://swift-tui.com/media/latest/todo.webp" width="400" alt="A to-do list: items checked off with confetti, then moving to the bottom.">
<br><strong>The little things.</strong> Confetti, and a finished item walking to the bottom of the list.
</td>
</tr>
</table>

## What's in the box

- **SwiftUI's API.** SwiftUI code compiles against TUI and means the same
  thing. What a terminal cannot honour fails to compile, rather than quietly
  doing nothing. See the
  [compatibility guide](<Documentation/SwiftUI parity/SwiftUI compatibility guide.md>)
  and the [deliberate deviations](<Documentation/SwiftUI parity/Deliberate deviations from SwiftUI.md>).
- **Keyboard first, mouse too.** Focus and Tab order, keyboard shortcuts and a
  menu bar; clicks, drags, scroll wheels and trackpads.
- **Every terminal, measured.** Ghostty, iTerm2, Apple's Terminal, Warp, kitty
  and more, each one's quirks measured and allowed for, in the
  [compatibility survey](<Documentation/Terminals/Terminal compatibility survey.md>).
- **Seven languages.** TUI's own words in English, German, French, Italian,
  Spanish, Chinese and Japanese, and your app's through the same service.
- **Idle is free.** A screen redraws only when something changed.
- **macOS, Linux and the browser.** [Try the demo](https://swift-tui.com/demo/)
  without installing anything.

## Getting started

Add TUI to your package:

```swift
dependencies: [
    .package(url: "https://github.com/wadetregaskis/TUI.git", branch: "main")
],
targets: [
    .executableTarget(name: "MyApp", dependencies: ["TUI"])
]
```

Then `import TUI`, and write views. The sample above is a whole app.

To see what TUI can do, run the Example app from a clone, and press `q` to
quit:

```bash
swift run Example
```

## Learn more

- **[Documentation](https://swift-tui.com/docs/documentation/tui/)**: the API
  reference and its articles, from getting started to the render cycle.
- **[Building and shipping an app](<Documentation/Building and shipping an app.md>)**:
  which products to depend on, what to ship, how small it can be.
- **[Contributing](CONTRIBUTING.md)**: how TUI is built, tested and laid out.
- **[Changes](CHANGELOG.md)**: what has changed, and what to do about it.

## License

MIT; see [LICENSE](LICENSE). TUI began as [Frank Gregor's TUIkit](https://github.com/phranck/TUIkit).
