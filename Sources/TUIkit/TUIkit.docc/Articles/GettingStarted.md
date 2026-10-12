# Getting Started

Build your first terminal application with TUIkit.

## Overview

TUIkit is a Swift package that lets you create terminal user interfaces with a declarative, SwiftUI-like syntax. This guide walks you through setting up a project and building a simple app.

## Adding TUIkit to Your Project

Add TUIkit as a dependency in your `Package.swift`:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MyTUIApp",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/wadetregaskis/TUIkit.git", branch: "main"),
    ],
    targets: [
        .executableTarget(
            name: "MyTUIApp",
            dependencies: ["TUIkit"]
        ),
    ]
)
```

The `TUIkit` product is the whole framework, and `import TUIkit` gives you all of it. An app can instead depend on
the products of only the modules it uses, and then compiles and links less: see <doc:ChoosingProducts>.

## Creating Your First App

Adopt the ``App`` protocol and mark it `@main`. Put it in a file called
anything **except** `main.swift` — `App.swift` is the convention, and the
`tuikit` scaffold generates exactly that:

```swift
import TUIkit

@main
struct MyApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        VStack {
            Text("Welcome to TUIkit!")
                .bold()
                .foregroundStyle(.cyan)

            Spacer()

            Text("Press 'q' to quit")
                .dim()
        }
    }
}
```

> Important: A file named `main.swift` holds top-level code, and Swift refuses
> `@main` in a module that has any — *"'main' attribute cannot be used in a
> module that contains top-level code"*. If you would rather have a
> `main.swift` (to run setup before the first frame, as this package's own
> `Example` target does), drop the attribute and call the entry point yourself:
>
> ```swift
> // main.swift — no @main on the type
> struct MyApp: App { … }
>
> registerMyLocalizations()
> await MyApp.main()
> ```

## Using State

Add interactivity with the ``State`` property wrapper:

```swift
struct CounterView: View {
    @State var count = 0

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

## One-Shot Rendering

For simple scripts that don't need a full app lifecycle, use ``renderOnce(content:)``:

```swift
import TUIkit

renderOnce {
    VStack {
        Text("Hello, TUIkit!")
            .bold()
            .foregroundStyle(.green)
        Divider()
        Text("Version \(tuiKitVersion)")
            .dim()
    }
}
```

## Build Time

A clean release build of TUIkit takes minutes (measured 2026-10-07, Swift 6.2.4, a 12-core arm64 Mac VM):

- If `swift --version` prints `Build config: +assertions`, your compiler is an assertions build, as swift.org's 6.2.4 for macOS is (swiftly's included). Xcode's own Swift of the same version compiled TUIkit in about 26% less time (86.4 s against 116.7 s to the end of TUIkit's compile). To build with it: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcrun swift build -c release`. Setting `DEVELOPER_DIR` alone does not redirect swiftly's `swift`.
- A release build compiles each module as one whole-module job, in a chain (TUIkitCore, then TUIkitView, then TUIkit), and most of each job runs on one thread, so more cores help little.

## Next Steps

- Learn about the framework's <doc:Architecture>
- Explore <doc:StateManagement> for reactive UIs
- Customize your app's look with <doc:ThemingGuide>
- Build multilingual apps with <doc:Localization>
