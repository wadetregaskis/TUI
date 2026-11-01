# Building Your First App

Grow a shopping list, one step at a time, into a small app that remembers what you put in it.

## Overview

In this tutorial you build Groceries, a shopping list that runs in the terminal. You'll start with a plain list, then add items, tick them off, save them between runs, confirm a clean-up in a sheet, and give the app keyboard shortcuts and a choice of colours.

Every step ends with something you can run. If you get stuck, <doc:Troubleshooting> covers the usual problems.

You need Swift 6.2 or later, and a real terminal: Apple's Terminal, iTerm2, Ghostty, or whatever you use on Linux. An IDE's output pane won't do, because it can't take key presses or draw a screen.

## Step 1: Show a list

Make a folder for the package, with a folder for its source inside:

```
mkdir Groceries
cd Groceries
mkdir -p Sources/Groceries
```

Save this as `Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Groceries",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/wadetregaskis/TUI.git", branch: "main"),
    ],
    targets: [
        .executableTarget(name: "Groceries", dependencies: ["TUI"]),
    ]
)
```

Save this as `Sources/Groceries/App.swift`. Name it anything but `main.swift`, which Swift treats differently.

```swift
import TUI

@main
struct Groceries: App {
    var body: some Scene {
        WindowGroup { ShoppingList() }
    }
}

struct ShoppingList: View {
    @State private var items = ["Apples", "Bread", "Coffee"]

    var body: some View {
        VStack(alignment: .leading) {
            List(items, id: \.self) { item in
                Text(item)
            }
        }
        .navigationTitle("Groceries")
    }
}
```

Now run it:

```
swift run
```

The first build downloads TUI and compiles it, which takes a few minutes. After that, builds take seconds. You'll see this, filling your terminal:

```
╭──────────────────────────────────────────────────────╮
│ Apples                                               │
│ Bread                                                │
│ Coffee                                               │
│                                                      │
│                                                      │
╰──────────────────────────────────────────────────────╯
```

Press the Down arrow to move through the rows, or type a letter to jump to the row that starts with it. The title doesn't take up a row on the screen. It goes in your terminal's window or tab title, in the terminals that show one.

Press Control-Q to quit.

## Step 2: Add items

To add items, the app needs somewhere to type. Replace `ShoppingList` with this:

```swift
struct ShoppingList: View {
    @State private var items = ["Apples", "Bread", "Coffee"]
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                TextField("Add an item", text: $newName)
                    .onSubmit(add)
                Button("Add", action: add)
            }
            List(items, id: \.self) { item in
                Text(item)
            }
        }
        .navigationTitle("Groceries")
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        items.append(name)
        newName = ""
    }
}
```

Run it again with `swift run`. The first control on the screen takes the keyboard, so you can start typing right away. Type `Milk` and press Return:

```
▐Add an item                                   ▌ ▐ Add ▌
╭──────────────────────────────────────────────────────╮
│ Apples                                               │
│ Bread                                                │
│ Coffee                                               │
│ Milk                                                 │
│                                                      │
╰──────────────────────────────────────────────────────╯
```

Press Tab to move to the next control and Shift-Tab to move back. With a mouse, you can click on any of them.

## Step 3: Tick items off

A plain string can't say whether it's been bought, so give each item a type of its own. Add `Item`, and replace `ShoppingList`:

```swift
struct Item: Identifiable {
    var id = UUID()
    var name: String
    var isBought = false
}

struct ShoppingList: View {
    @State private var items = [
        Item(name: "Apples"), Item(name: "Bread"), Item(name: "Coffee"),
    ]
    @State private var newName = ""

    private var bought: [Item] { items.filter(\.isBought) }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                TextField("Add an item", text: $newName)
                    .onSubmit(add)
                Button("Add", action: add)
            }
            List($items) { $item in
                Toggle(item.name, isOn: $item.isBought)
            }
            Text("\(items.count - bought.count) to buy")
        }
        .navigationTitle("Groceries")
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        items.append(Item(name: name))
        newName = ""
    }
}
```

`List($items)` hands each row a binding to its own item, so `$item.isBought` is all the toggle needs. Run it and click a checkbox, or press Tab until you reach one and press Space:

```
▐Add an item                                   ▌ ▐ Add ▌
╭──────────────────────────────────────────────────────╮
│ ■ Apples                                             │
│ □ Bread                                              │
│ □ Coffee                                             │
│                                                      │
│                                                      │
╰──────────────────────────────────────────────────────╯
2 to buy
```

Tab stops at the list first, then at each checkbox you can see. To reach one further down a long list, use the arrow keys while the list has the keyboard, and then press Tab.

## Step 4: Remember the list

Quit and run the app again, and your list is back to three items, because `@State` only lasts while the app runs. To keep it, store it with ``AppStorage``, which saves any `Codable` value.

Make `Item` `Codable`, and change one line of `ShoppingList`, the `items` property:

```swift
struct Item: Identifiable, Codable {
    var id = UUID()
    var name: String
    var isBought = false
}

struct ShoppingList: View {
    @AppStorage("items") private var items = [
        Item(name: "Apples"), Item(name: "Bread"), Item(name: "Coffee"),
    ]
    @State private var newName = ""

    private var bought: [Item] { items.filter(\.isBought) }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                TextField("Add an item", text: $newName)
                    .onSubmit(add)
                Button("Add", action: add)
            }
            List($items) { $item in
                Toggle(item.name, isOn: $item.isBought)
            }
            Text("\(items.count - bought.count) to buy")
        }
        .navigationTitle("Groceries")
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        items.append(Item(name: name))
        newName = ""
    }
}
```

Run it, add `Milk`, tick `Apples`, and quit with Control-Q. Run it again, and they're still there:

```
▐Add an item                                   ▌ ▐ Add ▌
╭──────────────────────────────────────────────────────╮
│ ■ Apples                                             │
│ □ Bread                                              │
│ □ Coffee                                             │
│ □ Milk                                               │
│                                                      │
╰──────────────────────────────────────────────────────╯
3 to buy
```

On a Mac the list goes in the app's `UserDefaults`, under the name `Groceries`. On Linux it goes in `~/.config/Groceries/settings.json`. To start again from three items, run `defaults delete Groceries` on a Mac, or delete that file on Linux.

## Step 5: Confirm in a sheet

Ticked items build up, so add a button that clears them. Clearing can't be undone, so it asks first, in a sheet.

Add `ClearSheet`, and replace `ShoppingList`:

```swift
struct ClearSheet: View {
    let names: [String]
    let clear: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading) {
            Text("Clear these from the list?").bold()
            ForEach(names, id: \.self) { name in
                Text(name)
            }
            HStack {
                Spacer()
                Button("Keep") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Clear", role: .destructive) {
                    clear()
                    dismiss()
                }
            }
        }
        .padding()
    }
}

struct ShoppingList: View {
    @AppStorage("items") private var items = [
        Item(name: "Apples"), Item(name: "Bread"), Item(name: "Coffee"),
    ]
    @State private var newName = ""
    @State private var isConfirmingClear = false

    private var bought: [Item] { items.filter(\.isBought) }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                TextField("Add an item", text: $newName)
                    .onSubmit(add)
                Button("Add", action: add)
            }
            List($items) { $item in
                Toggle(item.name, isOn: $item.isBought)
            }
            HStack {
                Text("\(items.count - bought.count) to buy")
                Spacer()
                Button("Clear bought…") { isConfirmingClear = true }
                    .disabled(bought.isEmpty)
            }
        }
        .navigationTitle("Groceries")
        .sheet(isPresented: $isConfirmingClear) {
            ClearSheet(names: bought.map(\.name)) {
                items.removeAll(where: \.isBought)
            }
        }
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        items.append(Item(name: name))
        newName = ""
    }
}
```

Tick something and click **Clear bought…**, or press Tab until you reach it and press Return:

```
▐Add an item                                   ▌ ▐ Add ▌
╭──────────────────────────────────────────────────────╮
│ ■ Apples                                             │

 Clear these from the list?
 Apples
                                     ▐ Keep ▌ ▐ Clear ▌

│                                                      │
╰──────────────────────────────────────────────────────╯
2 to buy                               ▐ Clear bought… ▌
```

The sheet's first button takes the keyboard, so a stray Return keeps your items. Press Tab and Return to clear them, or click **Clear**. Escape presses **Keep** from anywhere in the sheet, which is what `.cancelAction` means. `dismiss` closes the sheet here, not the app: it closes whatever the view is inside.

## Step 6: Add shortcuts and a theme

Last, two finishing touches: a shortcut to clear bought items, and a choice of colours that the app remembers. A palette sets all the colours of the views inside it, and ``PaletteRegistry`` lists the ones that come with TUI.

This is the whole of `App.swift` now, with the two additions in `ShoppingList`:

```swift
import TUI

@main
struct Groceries: App {
    var body: some Scene {
        WindowGroup { ShoppingList() }
    }
}

struct Item: Identifiable, Codable {
    var id = UUID()
    var name: String
    var isBought = false
}

struct ClearSheet: View {
    let names: [String]
    let clear: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading) {
            Text("Clear these from the list?").bold()
            ForEach(names, id: \.self) { name in
                Text(name)
            }
            HStack {
                Spacer()
                Button("Keep") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Clear", role: .destructive) {
                    clear()
                    dismiss()
                }
            }
        }
        .padding()
    }
}

struct ShoppingList: View {
    @AppStorage("items") private var items = [
        Item(name: "Apples"), Item(name: "Bread"), Item(name: "Coffee"),
    ]
    @AppStorage("theme") private var theme = 0
    @State private var newName = ""
    @State private var isConfirmingClear = false

    private var bought: [Item] { items.filter(\.isBought) }
    private var palettes: [any Palette] { PaletteRegistry.all }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                TextField("Add an item", text: $newName)
                    .onSubmit(add)
                Button("Add", action: add)
            }
            List($items) { $item in
                Toggle(item.name, isOn: $item.isBought)
            }
            HStack {
                Text("\(items.count - bought.count) to buy")
                Spacer()
                Button("Theme") { theme = (theme + 1) % palettes.count }
                    .keyboardShortcut("t")
                Button("Clear bought…") { isConfirmingClear = true }
                    .keyboardShortcut("k")
                    .disabled(bought.isEmpty)
            }
        }
        .navigationTitle("Groceries")
        .sheet(isPresented: $isConfirmingClear) {
            ClearSheet(names: bought.map(\.name)) {
                items.removeAll(where: \.isBought)
            }
        }
        .palette(palettes[theme % palettes.count])
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        items.append(Item(name: name))
        newName = ""
    }
}
```

Run it one last time:

```
▐Add an item                                   ▌ ▐ Add ▌
╭──────────────────────────────────────────────────────╮
│ □ Apples                                             │
│ □ Bread                                              │
│ □ Coffee                                             │
│                                                      │
│                                                      │
╰──────────────────────────────────────────────────────╯
3 to buy                     ▐ Theme ▌ ▐ Clear bought… ▌
```

A SwiftUI shortcut written for ⌘ answers to Control here, because most terminals keep ⌘ for themselves. So press Control-T to step through the palettes, and Control-K to bring up the sheet, whether or not the text field has the keyboard. Quit and run again, and the app comes back in the colours you left it in.

## Where to go next

You've used most of what a small app needs. To take Groceries further:

- Learn the differences you've met here, such as Control for ⌘, in <doc:ComingFromSwiftUI>.
- Show each item's details with <doc:Navigation>.
- Split the app into smaller views and share a model between them with <doc:StateManagement>.
- Add sections and reordering with <doc:ListAndTable>.
- Show the shortcuts along the bottom of the screen with <doc:StatusBarGuide>.
- Make your own colours with <doc:ThemingGuide>.
- Build a version to give to other people. `swift build -c release` makes one that's smaller and faster than the debug build `swift run` gives you, and <doc:ShippingAnApp> says what to ship and how to make it smaller still.
