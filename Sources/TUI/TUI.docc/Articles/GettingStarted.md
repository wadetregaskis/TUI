# Getting Started

Create a terminal app with TUI, run it, and make it respond to a key press.

## Overview

You need Swift 6.2 or newer, which on a Mac comes with Xcode 26 or its Command Line Tools. Swift's package manager does the rest, so there is nothing else to install. Your app will run on macOS 14 or later, and on Linux.

## Create a Package

In a terminal, make a folder for your app and create an executable package in it:

```bash
mkdir MyTUIApp
cd MyTUIApp
swift package init --type executable
```

That writes a `Package.swift` and one source file, `Sources/MyTUIApp/MyTUIApp.swift`.

## Add TUI

Replace everything in `Package.swift` with this:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MyTUIApp",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/wadetregaskis/TUI.git", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "MyTUIApp",
            dependencies: ["TUI"]
        ),
    ]
)
```

## Write the App

Open `Sources/MyTUIApp/MyTUIApp.swift`. It holds a small `@main` type that prints "Hello, world!". Your app takes its place, so replace everything in the file with this:

```swift
import TUI

@main
struct MyTUIApp: App {
    var body: some Scene {
        WindowGroup {
            VStack {
                Text("Hello, TUI!")
                    .bold()
                Text("Press q to quit")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
```

## Run It

```bash
swift run
```

The first run downloads and compiles TUI, which takes a few minutes. Later runs take seconds.

The terminal clears, and your two lines of text appear in the middle of it. Press `q` to quit, and the terminal goes back to how it was.

## Count Something

Now give it some state and a button. Replace everything in the file again:

```swift
import TUI

@main
struct MyTUIApp: App {
    var body: some Scene {
        WindowGroup {
            CounterView()
        }
    }
}

struct CounterView: View {
    @State private var count = 0

    var body: some View {
        VStack {
            Text("Count: \(count)")
                .bold()
            Button("Increment") {
                count += 1
            }
        }
    }
}
```

Run it with `swift run` again. The button has the keyboard focus already, because it's the only control on the screen. Press Return or Space to press it, or click it with the mouse, and the count goes up.

If you know SwiftUI, this is the same code you would write there.

## Quitting

`q` quits from anywhere, as long as the control with the focus isn't using the letter itself. A text field types it, and a list or table uses it to jump to a row starting with "q". Press Tab to move the focus to another control, then press `q`.

Control-\\ always quits, and it works even if the app has stopped responding. Your shell may then print `Quit: 3`, which only says how the app ended.

Control-C doesn't quit by default. It reaches your app as an ordinary key.

<doc:KeyboardShortcuts#Default-Bindings> shows how to change the quit key.

## Next

- <doc:ComingFromSwiftUI>, if you already know SwiftUI
- <doc:StateManagement>, to keep and share your app's data
- <doc:ListAndTable>, to show rows of data
- <doc:Controls>, for every button, field, toggle and picker
