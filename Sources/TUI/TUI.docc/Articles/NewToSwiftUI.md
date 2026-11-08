# New to SwiftUI

The ideas behind TUI's code, explained for people who have never written SwiftUI.

## Overview

TUI uses the same programming interface as SwiftUI, Apple's framework for app interfaces. You don't need a Mac, Xcode or any SwiftUI experience to use it, but the code looks unusual if you're used to drawing a screen yourself. This page explains the ideas behind that code, one at a time, each with a short example you can run.

To run an example, make the app in <doc:GettingStarted>, then put the example's view in the `WindowGroup`, in place of `CounterView()`. Press Control-Q to quit.

If you know another terminal UI framework, the pages that compare it with TUI are listed at the end of this page.

## The Swift You Need

Five pieces of Swift come up on every page:

- **`struct`** declares a value type, and **`let`** and **`var`** declare a constant and a variable. A struct is copied when you pass it, like an integer.
- **Closures** are blocks of code you can pass around: `{ count += 1 }`. When a closure is a function's last argument, it can go after the parentheses: `Button("Add") { count += 1 }` is `Button("Add", action: { count += 1 })`.
- **Optionals**: `String?` is a `String` or `nil`, and `name ?? "none"` gives `"none"` when `name` is `nil`.
- **String interpolation**: `"Count: \(count)"` puts `count`'s value in the string.
- **`@` before a name**, as in `@State` or `@main`, is an attribute. Each one is explained where it first appears.

## A Program Describes a Screen

A TUI program doesn't print anything and doesn't run a loop. It describes what the screen should show, and TUI draws it, reads the keyboard and mouse, and draws again when something changes.

```swift
import TUI

@main
struct HelloApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Hello")
        }
    }
}
```

`@main` marks where the program starts. An ``App`` has a `body` of *scenes*, and ``WindowGroup`` is the scene that fills the terminal. Its contents are *views*: here one ``Text``.

In a toolkit where you draw the screen yourself, the same program might look like this:

```text
init_screen()
loop:
    clear()
    draw_text(0, 0, "Hello")
    refresh()
    key = read_key()
    if key == quit_key: break
restore_screen()
```

In TUI the loop, the clearing, the drawing and the clean-up on exit are all done for you.

## A View Is a Value

A view is a small struct with one property, `body`, which says what the view is made of:

```swift
struct Greeting: View {
    let name: String

    var body: some View {
        Text("Hello, \(name)")
    }
}
```

Use it as `Greeting(name: "Ada")`. A view isn't a widget that stays on the screen: it's a description, cheap to make. TUI calls `body` whenever it needs to know what to show, and builds new view values each time, so a view keeps no data of its own between calls. Its data lives in the property wrappers in <doc:NewToSwiftUI#State-Belongs-to-the-View>.

`some View` means "a view, of one particular type that the compiler works out from the code in `body`". You don't have to name that type, which can be long.

## Lists of Views: Result Builders

Inside the braces of `body` and of containers such as ``VStack``, you list views one after another, with no commas and no `return`:

```swift
struct Labels: View {
    let showHint: Bool

    var body: some View {
        VStack {
            Text("Title").bold()
            Text("Subtitle")
            if showHint {
                Text("Press Tab to move")
            }
        }
    }
}
```

This works because those closures are *view builders*, marked with ``ViewBuilder``. Swift turns each line into a view and combines them into one. An `if` adds its view only when the condition holds, and a `ForEach` (in <doc:NewToSwiftUI#Lists-and-Identity>) adds one per item. You'll see `@ViewBuilder` on your own properties and parameters when they hold views in the same way.

``VStack`` places views top to bottom, ``HStack`` left to right, and ``ZStack`` on top of each other. ``Spacer`` fills the space between them. Sizes are counted in character cells: `.padding(1)` is one column or row.

## Modifiers, and Why Their Order Matters

A *modifier* is a method you call on a view, such as `.bold()`, `.padding()` or `.border()`. It doesn't change the view. It returns a new view that wraps the old one, so each modifier applies to everything before it:

```swift
struct OrderMatters: View {
    var body: some View {
        HStack {
            Text("Hi").padding().border()
            Text("Hi").border().padding()
        }
    }
}
```

The first `Text` gets padding, and the border goes around the padded text. The second gets a border, and the padding goes outside it, as a blank cell between the border and its neighbours. (A border also keeps one column clear on each side of what it holds.)

```text
╭──────╮
│      │  ╭────╮
│  Hi  │  │ Hi │
│      │  ╰────╯
╰──────╯
```

So read a chain of modifiers from the inside out, as layers added one at a time. A modifier on a container reaches everything inside it: `VStack { … }.foregroundStyle(.red)` colours every `Text` in the stack.

## State Belongs to the View

A view's struct is rebuilt every time, so an ordinary `var` in it would start again from its first value. To keep a value, mark it with ``State``:

```swift
struct Counter: View {
    @State private var count = 0

    var body: some View {
        VStack {
            Text("Count: \(count)")
            Button("Add One") { count += 1 }
        }
    }
}
```

TUI keeps `count` outside the struct, in storage that lasts as long as the view is on screen, and gives the same value to every new copy of `Counter`. When the button changes `count`, TUI calls `body` again and redraws what changed. You never call a redraw yourself. The `= 0` is used only the first time.

Mark it `private`: state belongs to the view that declares it, and a value passed in from outside wouldn't replace it after the first time.

An imperative version keeps the counter in a variable of its own and has to redraw the label by hand:

```text
count = 0
on_button_pressed:
    count = count + 1
    label.set_text("Count: " + count)
    redraw()
```

## Passing State Down: Bindings

A child view sometimes needs to change a value that its parent owns. Pass it a ``Binding``, a two-way link to the value, by writing `$` before the state's name:

```swift
struct Settings: View {
    @State private var sound = true

    var body: some View {
        VStack {
            SoundSwitch(isOn: $sound)
            Text(sound ? "Sound on" : "Sound off")
        }
    }
}

struct SoundSwitch: View {
    @Binding var isOn: Bool

    var body: some View {
        Toggle("Sound", isOn: $isOn)
    }
}
```

`SoundSwitch` doesn't own the value: it reads and writes `Settings`' `sound` through the binding, so both views always agree. Built-in controls work the same way: a ``Toggle``, a ``TextField`` or a ``List`` with a selection each takes a binding to the value it edits.

## What a Property Wrapper Is

`@State` and `@Binding` are *property wrappers*: a type that stands between a property and the code using it, and decides how its value is stored. Reading `count` reads the stored value. Writing `$count` gives you the wrapper's *projected value*, which for `@State` and `@Binding` is a binding. That's all the `$` means. You'll meet a few more:

| Wrapper | Holds |
|---|---|
| `@State` | a value the view owns |
| `@Binding` | a link to a value something else owns |
| `@Environment` | a value handed down the view tree, such as the colour scheme |
| `@FocusState` | which control has the keyboard focus |
| `@AppStorage` | a setting saved between runs of the app |

## Sharing Data: Observable Classes

When several views share data, or the data has logic of its own, put it in a class marked `@Observable`:

```swift
@Observable
final class Basket {
    var items: [String] = []
}

struct Shop: View {
    @State private var basket = Basket()

    var body: some View {
        VStack {
            Text("\(basket.items.count) items")
            AddButton(basket: basket)
        }
    }
}

struct AddButton: View {
    let basket: Basket

    var body: some View {
        Button("Add an Apple") { basket.items.append("Apple") }
    }
}
```

A class is passed by reference, so `Shop` and `AddButton` share one basket. `@Observable` records which properties each view's `body` read, and redraws a view when one of those changes. The view that creates the object keeps it in `@State`, so it survives the view being rebuilt. <doc:StateManagement> covers this in full.

## The Environment

Some values reach every view below the place you set them, without being passed by hand. This is the *environment*. Modifiers such as `.foregroundStyle(_:)` and `.disabled(_:)` set values in it, and a view reads one with `@Environment`:

```swift
struct Panel: View {
    var body: some View {
        VStack {
            Button("Save") {}
            StatusLabel()
        }
        .disabled(true)
    }
}

struct StatusLabel: View {
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Text(isEnabled ? "Ready" : "Locked")
    }
}
```

`.disabled(true)` on the stack disables the button and everything else inside it, and `StatusLabel` reads the same value and shows "Locked". You can add values of your own: see <doc:StateManagement>.

## Lists and Identity

``ForEach`` makes one view for each item in a collection. TUI needs to know which item is which from one redraw to the next, so it can keep each row's state and selection with the right item when the collection changes. That is the item's *identity*, and you give it with `id:` or by making the item `Identifiable`:

```swift
struct Chore: Identifiable {
    let id: Int
    var title: String
}

struct ChoreList: View {
    @State private var chores = [
        Chore(id: 1, title: "Shop"),
        Chore(id: 2, title: "Cook"),
    ]
    @State private var selection: Int?

    var body: some View {
        VStack {
            List(selection: $selection) {
                ForEach(chores) { chore in
                    Text(chore.title)
                }
            }
            Text("Selected: \(selection.map(String.init) ?? "none")")
        }
    }
}
```

A list's selection is the identity of the selected row: here an `Int?`, the `id` of one chore or `nil`. A `Set<Int>` instead lets people select several. The arrow keys move the list's cursor, and Space or Return selects the row under it. For strings that are unique, `ForEach(names, id: \.self)` uses each string as its own identity.

Keep identities stable. If a row's id changes, TUI treats it as a new row: its state starts again and it loses the selection.

## Focus and Keys

One control at a time has the keyboard focus, and keys go to it. Tab and Shift-Tab move the focus, and the arrow keys do too once the focused control has no use for them. Buttons, fields, toggles and lists take part by themselves, and the first one on the screen starts with the focus.

To respond to a key, add `.onKeyPress`. It hears keys while the focus is on its view or inside it, so a handler on a container hears every key the focused control doesn't use:

```swift
struct Scoreboard: View {
    @State private var score = 0

    var body: some View {
        VStack {
            Text("Score: \(score)")
            Button("Reset") { score = 0 }
        }
        .onKeyPress("+") {
            score += 1
            return .handled
        }
    }
}
```

A view that isn't a control, such as a `Text`, hears no keys until you make it `.focusable()`. To move the focus from code, use ``FocusState``. A button can also have a shortcut that works wherever the focus is: `.keyboardShortcut("s")` answers to Control-S. See <doc:FocusSystem> and <doc:KeyboardShortcuts>.

## Doing Work Over Time

`body` only describes the screen, so it must not wait, sleep or read files. Start work from a modifier instead:

```swift
struct Clock: View {
    @State private var seconds = 0

    var body: some View {
        Text("Running for \(seconds) s")
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    seconds += 1
                }
            }
    }
}
```

`.task` runs its code when the view appears and cancels it when the view goes away. `.onAppear` runs a quick action when the view appears, and `.onChange(of:)` runs one when a value changes.

## Words You Will Meet

| Word | Meaning |
|---|---|
| View | A value that describes part of the screen, with a `body` |
| Scene | A top-level piece of an app, such as a `WindowGroup` |
| Modifier | A method that wraps a view in a new one, such as `.padding()` |
| State | A value a view owns, kept between redraws |
| Binding | A two-way link to a value something else owns, written `$name` |
| Environment | Values handed down to every view below where they're set |
| Identity | How TUI tells one view, or one row, from another between redraws |
| View builder | The braces where you list views without commas |
| Focus | Which control the keyboard goes to |
| Cell | One character position in the terminal, the unit of every size |

## Coming From Another Framework

If you've used another UI framework, these pages map what you know onto TUI:

- <doc:ComingFromSwiftUI>, for SwiftUI itself
- <doc:ComingFromBubbleTea>, for Go's Bubble Tea and Lip Gloss
- <doc:ComingFromRatatui>, for Rust's Ratatui

Then carry on with <doc:BuildingYourFirstApp>, which builds a small app step by step.
