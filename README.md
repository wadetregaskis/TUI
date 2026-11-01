<h1 align="center">TUI</h1>

<p align="center"><strong>The Swift Terminal UI framework.</strong></p>

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

Write SwiftUI, and get a terminal app. TUI speaks SwiftUI's language, with a terminal accent.  Views, `@State`, `@Observable`, stacks, lists, tables, navigation, sheets, menus, animation, and so much more. It draws them with nothing but Swift and the terminal's own escape codes: no ncurses, nothing to install. It runs on macOS, Linux, and in a web browser (and anywhere else that supports WebAssembly).

> [!IMPORTANT]
> TUI is close to a 1.0 release, but not there yet.  Until then, breaking changes may occur without notice.

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

If you know SwiftUI, the code above should look very familiar to you (because the above example is 100% valid SwiftUI _and_ TUI).  That's the point - you can write beautiful, powerful terminal apps the same way you write beautiful, powerful GUI Mac, iPad, or iPhone apps.

TUI's goal is not "write once run anywhere", it's "learn once write anywhere".  There are substantial intrinsic differences between a GUI and a terminal - but using SwiftUI concepts, patterns, and (where applicable) compatible APIs, makes it _easy_ (and you _can_ share a lot of UI code directly, too).

But you don't have to know SwiftUI - or be tied to Apple's platforms.  TUI works on Linux and the web (via WASM), too - and it's just a great framework for producing wonderful terminal apps.

## In a real terminal

Actual screen recordings (demo apps, but otherwise completely real - see [their source code](Tools/ScreenClips) yourself).

<table>
<tr>
<td width="50%" valign="top">
<img src="https://swift-tui.com/media/latest/images.webp" width="400" alt="A picture viewer stepping through wildlife photographs, drawn as real pixels.">
<br><strong>Real pictures.</strong> Images draw natively, through the Kitty Graphics Protocol (in terminal clients which support it).
</td>
<td width="50%" valign="top">
<img src="https://swift-tui.com/media/latest/glyphs.webp" width="400" alt="The same kind of picture drawn in text characters, its style changed in an inspector.">
<br><strong>…or Unicode art, everywhere else.</strong> Highly customisable - glyph sets, shape matching, palettes, dithering, tone curves, and much more.
</td>
</tr>
<tr>
<td valign="top">
<img src="https://swift-tui.com/media/latest/tables.webp" width="400" alt="An activity monitor's process table: scrolled, sorted by column, a row followed, filtered by name.">
<br><strong>Powerful tables.</strong> Alignment, sorting, reordering, headers & sections, searching, and more.
</td>
<td valign="top">
<img src="https://swift-tui.com/media/latest/dragdrop.webp" width="400" alt="A task board whose cards are dragged between columns, three at once.">
<br><strong>Drag and drop.</strong> Use the mouse or the keyboard.  Built-in support in Tables, Lists, and more, and easily implemented by custom views.
</td>
</tr>
<tr>
<td valign="top">
<img src="https://swift-tui.com/media/latest/materials.webp" width="400" alt="A photo album with a share panel and a toast on frosted glass over it.">
<br><strong>Materials.</strong> Beautiful effects, like frosted glass, over the terminal's own pixels.
</td>
<td valign="top">
<img src="https://swift-tui.com/media/latest/animation.webp" width="400" alt="A card game: spells cast from a hand of cards, with a battle log.">
<br><strong>Animation.</strong> Your app comes alive with a powerful animation engine, featuring spring physics and support for custom curves.
</td>
</tr>
<tr>
<td valign="top">
<img src="https://swift-tui.com/media/latest/navigation.webp" width="400" alt="A field guide in a three-column split view; a photo zooms up into a screen of its own.">
<br><strong>Navigation.</strong> Go beyond mere buttons and fixed layouts - utilise Navigation Views, Split Views, and more.
</td>
<td valign="top">
<img src="https://swift-tui.com/media/latest/document.webp" width="400" alt="A postcard app: a picture picked in an open panel, saved, exported as Markdown.">
<br><strong>Documents.</strong> The full document lifecycle, from new / open dialog to save dialog.
</td>
</tr>
<tr>
<td valign="top">
<img src="https://swift-tui.com/media/latest/controls.webp" width="400" alt="An event planner filled in from the keyboard: fields, a pop-up, a stepper, a calendar.">
<br><strong>Controls.</strong> Text fields, buttons, pop-up menus, toggles, radio buttons, steppers, sliders, gauges, date pickers, and so much more.
</td>
<td valign="top">
<img src="https://swift-tui.com/media/latest/styles.webp" width="400" alt="A train booking form whose controls change their look every two seconds.">
<br><strong>Styles.</strong> Find your own unique look - customise backgrounds, shapes, borders, iconography, and more.
</td>
</tr>
<tr>
<td valign="top">
<img src="https://swift-tui.com/media/latest/theming.webp" width="400" alt="A build window whose colours and borders change while it runs.">
<br><strong>Themes.</strong> Over a dozen built-in, plus completely custom palettes of your choosing.
</td>
<td valign="top">
<img src="https://swift-tui.com/media/latest/tracks.webp" width="400" alt="A backup's progress bar, restyled as it fills, and a bandwidth slider.">
<br><strong>Progress and sliders</strong> in any style you can dream up.
</td>
</tr>
<tr>
<td valign="top">
<img src="https://swift-tui.com/media/latest/menus.webp" width="400" alt="A mail client's menu bar and context menu in Apple's Terminal.">
<br><strong>Menus.</strong> A full menu bar, plus contextual & pop-up menus, all fully accessible by mouse or keyboard.
</td>
<td valign="top">
<img src="https://swift-tui.com/media/latest/textedit.webp" width="400" alt="A notes editor in Warp: text selected with the mouse, dragged to a new place, edited.">
<br><strong>Text editing.</strong> All the text navigation & editing features you expect - including full mouse, drag & drop, selection, and clipboard support.
</td>
</tr>
<tr>
<td valign="top">
<img src="https://swift-tui.com/media/latest/unicode.webp" width="400" alt="One screen of languages and scripts in Ghostty, iTerm2, Apple's Terminal and Warp.">
<br><strong>Maximum compatibility.</strong> Every terminal client has its own quirks and rendering bugs - TUI deals with it so you don't have to.
</td>
<td valign="top">
<img src="https://swift-tui.com/media/latest/todo.webp" width="400" alt="A to-do list: items checked off with confetti, then moving to the bottom.">
<br><strong>The little things.</strong> Why let the GUIs have all the fun?
</td>
</tr>
</table>

## What's in the box

- **SwiftUI-compatible API.** Most SwiftUI code compiles as-is under TUI, and behaves effectively the same.  Some things differ, but are easily adapted (e.g. the terminal's primary unit is the character cell, not the pixel, so instead of `.padding(20)` you might write `.padding(1)`).  See [Coming from SwiftUI](https://swift-tui.com/docs/documentation/tui/comingfromswiftui) for what's different.
- **Keyboard first, mouse too.** Everything is designed to be terminal-native, which means proper support for keyboard-only use.  But TUI also loves the mouse, and its extensive and powerful mouse support makes terminal apps much more intuitive for beginners.
- **Powerful terminal client portability.** Terminal clients are _not_ created equal - you wouldn't believe how much they vary in what they support, how they support it, and where they make mistakes.  TUI has extensive knowledge of popular terminal clients - including Apple Terminal, iTerm2, Ghostty, & Warp - which means you don't have to.
- **Seven languages.** TUI's built-in controls support multiple languages, with full localisation support - for both your own custom controls and additional languages.  See your app in English, German, French, Italian, Spanish, Chinese, Japanese - and any others you wish to add.
- **Performance.** Aesthetics _do_ matter, but they're worthless if the everyday experience isn't fast and smooth.  Creating & rendering complex terminal UIs isn't easy, but TUI has invested the blood, sweat, and tears to make sure that for _you_ it is - _without_ compromising on performance.
- **Platform portability.** Built to provide a native experience on macOS and Linux, but one more thing - the web!  [Try the demo](https://swift-tui.com/demo/) right in your web browser, no installation or plug-ins required!
- **Open & free.** It's all here - see the source for yourself, use it freely and widely.  Make changes - send in your pull requests!  And can't figure out what the heck is wrong with your SwiftUI app because SwiftUI is closed-source and inscrutable?  Try running it under TUI, where you can see _exactly_ what's going on, stepping through the full stack line by line.  Fixes you make under TUI often apply under SwiftUI, thanks to the similar view model & render engine.

## Getting started

Add TUI to your package:

```swift
platforms: [.macOS(.v15)],
dependencies: [
    .package(url: "https://github.com/wadetregaskis/TUI.git", branch: "main")
],
targets: [
    .executableTarget(name: "MyApp", dependencies: ["TUI"])
]
```

Then `import TUI`, and start writing your views.  [Getting Started](https://swift-tui.com/docs/documentation/tui/gettingstarted) goes through it step by step, from an empty folder to a running app.

To see more of what TUI can do, run the Example app (`swift run Example` from a checkout / clone).  Then, check out [its source](Sources/Example/) to see how it's done, and copy whatever you need to get started on your own app.

## Learn more

- **[Getting Started](https://swift-tui.com/docs/documentation/tui/gettingstarted)**: create your first app, run it, and quit it.
- **[Documentation](https://swift-tui.com/docs/documentation/tui/)**: the API reference and its articles, from getting started to the render cycle.
- **[Testing your app](https://swift-tui.com/docs/documentation/tui/testingyourapp)**: run your views in a unit test, press keys, move a clock by hand and read the screen.
- **[Building and shipping an app](https://swift-tui.com/docs/documentation/tui/shippinganapp)**: what to ship, how small it can be, and why a release build takes minutes.
- **[Contributing](CONTRIBUTING.md)**: how TUI is built, tested and laid out.
- **[Changes](CHANGELOG.md)**: what has changed, and what to do about it.

## License

MIT; see [LICENSE](LICENSE).

## Credits

TUI began as [Frank Gregor](https://github.com/phranck)'s [TUIkit](https://github.com/phranck/TUIkit).  Circa May 2026, [Wade Tregaskis](https://github.com/wadetregaskis) saw it and was inspired - what an awesome idea!  And what an interesting project to explore Claude-driven development with… and thus what was initially a "huh, neat, I wonder if I can add a few features…?" turned into a long quest to complete the vision and bring to life the most powerful, easy-to-use terminal UI framework.

**Big thanks** to Frank for inspiring this project and laying the groundwork.
