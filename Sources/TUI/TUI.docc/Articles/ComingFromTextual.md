# Coming from Textual

Map what you know from Textual onto TUI.

## Overview

Textual, the Python framework, keeps a tree of widget objects, styles them with CSS, and passes messages up the tree. You change the screen by changing those widgets: updating a label, mounting a new widget, querying one by its id. TUI has no widget objects to change. A view is a value that describes part of the screen, and you change the screen by changing the state it was made from. TUI then calls `body` again and draws what changed.

If `@State`, `body` or modifiers are new to you, read <doc:NewToSwiftUI> first. The Python code on this page is for Textual 8.

## The Same App in Both

A counter that `+` increases, and a list of three fruits with one selected. In Textual:

```python
from textual import on
from textual.app import App, ComposeResult
from textual.reactive import reactive
from textual.widgets import Label, ListItem, ListView

FRUIT = ["Apples", "Bananas", "Cherries"]


class FruitApp(App):
    BINDINGS = [("plus", "increment", "Increment"), ("q", "quit", "Quit")]

    count = reactive(0, init=False)

    def compose(self) -> ComposeResult:
        yield Label("Count: 0", id="count")
        yield ListView(*(ListItem(Label(name)) for name in FRUIT))
        yield Label(id="selected")

    def watch_count(self, count: int) -> None:
        self.query_one("#count", Label).update(f"Count: {count}")

    def action_increment(self) -> None:
        self.count += 1

    @on(ListView.Highlighted)
    def show_selection(self, event: ListView.Highlighted) -> None:
        if event.list_view.index is not None:
            text = f"Selected: {FRUIT[event.list_view.index]}"
            self.query_one("#selected", Label).update(text)


if __name__ == "__main__":
    FruitApp().run()
```

In TUI:

```swift
import TUI

@main
struct FruitApp: App {
    var body: some Scene {
        WindowGroup { FruitView() }
    }
}

struct FruitView: View {
    @State private var count = 0
    @State private var selection: String? = "Apples"
    private let fruit = ["Apples", "Bananas", "Cherries"]

    var body: some View {
        VStack(alignment: .leading) {
            Text("Count: \(count)")
            List(fruit, id: \.self, selection: $selection) { name in
                Text(name)
            }
            Text("Selected: \(selection ?? "none")")
        }
        .onKeyPress("+") {
            count += 1
            return .handled
        }
    }
}
```

There's no `watch_count` and no `query_one`: both labels read the state directly, so they're right whenever TUI draws them. The arrow keys move the list's cursor, and Space or Return selects the row under it. Control-Q quits.

## Concepts

| Textual | TUI |
|---|---|
| `class MyApp(App)` and `compose()` yielding widgets | `struct MyApp: App` with a `body` of scenes, and views whose `body` returns other views |
| A `Widget` subclass with `render()` or `compose()` | A ``View`` struct with a `body`. It's a value, rebuilt often, not an object you keep |
| `reactive(0)` | `@State private var count = 0`. Any view that reads it is redrawn when it changes |
| `watch_count` | `.onChange(of: count) { … }`, though usually there's nothing to do: the views read `count` directly |
| `compute_total` | An ordinary computed property: `var total: Int { a + b }` |
| `on_button_pressed`, `@on(Button.Pressed, "#id")` | The closure you give the control: `Button("Add") { count += 1 }`. Nothing is looked up by name |
| Custom messages, `post_message`, bubbling | A closure or a `@Binding` passed to the child, an `@Observable` object, or for distant views `@Environment` and ``PreferenceKey`` |
| `query_one("#id")` and changing the widget | Nothing to query. Change the state the view was made from |
| `mount()` and `remove()` | An `if` or a `ForEach` in `body`. Views appear and disappear as the state changes |
| CSS, selectors, classes and `$variables` | Modifiers on the views, and themes set in the environment, which restyle everything below them: see <doc:ThemingGuide> |
| `Vertical`, `Horizontal`, `Grid`, `layout: grid` | ``VStack``, ``HStack``, ``Grid`` |
| `BINDINGS` and `action_*` methods | `.keyboardShortcut` on a button, `.onKeyPress` on a view, and `.statusBarItems` to list keys in the status bar, as Textual's `Footer` does |
| `can_focus`, `:focus`, `focus()` | `.focusable()`, ``FocusState`` and `.focused(_:equals:)`. The focused control is drawn as focused for you |
| `push_screen`, `pop_screen`, `ModalScreen` | ``NavigationStack``, `.sheet`, `.alert`: see <doc:Navigation> and <doc:Presentation> |
| `@work`, `run_worker`, `set_interval` | `.task { … }`, which runs async code and is cancelled when the view goes away, and ``TimelineView`` |
| `DataTable`, `Tree`, `TabbedContent`, `Input`, `TextArea`, `Select`, `ListView`, `OptionList` | ``Table``, ``OutlineGroup``, ``TabView``, ``TextField``, ``TextEditor``, ``Picker``, ``List`` |
| `App.run_test()` and `Pilot` | ``TestApp`` in the `TUITesting` product: see <doc:TestingYourApp> |

## What Will Surprise You

- **You can't hold on to a view.** There's no reference to keep and no method to call on it later. Anything that should change belongs in state, and the view reads it.
- **No stylesheet.** Style goes on the views, as modifiers, and a modifier on a container reaches everything inside it: `.foregroundStyle(.red)` on a stack colours every `Text` in it. There are no selectors, so to style several views alike, write a `ViewModifier` of your own or a small view that applies the modifiers.
- **Types are checked when you build.** A misspelt property or a wrong argument is a compile error, not an exception at run time. In return there's a compile step: `swift run` rebuilds before it runs.
- **State must be marked.** A plain `var` in a view struct starts again every time the view is rebuilt. Keep values in `@State`.
- **Control-C doesn't quit.** It copies the selection. Control-Q quits.
- **The app takes the whole screen.** TUI has no inline mode like `run(inline=True)`.
- **No Windows yet.** TUI apps run on macOS and Linux. Textual runs on Windows too.

## What TUI Adds

- **A native binary.** Nothing to install on the machine that runs it, no interpreter, and quick to start.
- **Checks at compile time**, on everything from a property's name to which views a container can hold.
- **The mouse and the focus work alike in every control**, from the start, with nothing to wire up.
- **SwiftUI's interface.** What you learn carries over to SwiftUI apps for Apple's platforms, and much SwiftUI code compiles here unchanged. See <doc:ComingFromSwiftUI>.

## What Textual Does Better

- **CSS.** Restyle an app without touching its code, with selectors and variables, and see each edit live with `textual run --dev`.
- **Developer tools.** `textual console` shows your logs and messages while the app runs.
- **The browser.** `textual serve` puts any Textual app in a web page. TUI's own demo runs in a browser too, as WebAssembly, but that takes a build of its own.
- **More widgets**, such as `Sparkline`, `Markdown` and `Log`, and Python's quick edit-and-run loop.
- **Inline mode and Windows**, neither of which TUI has yet.
