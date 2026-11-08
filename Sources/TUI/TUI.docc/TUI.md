# ``TUI``

The Swift Terminal UI framework: write SwiftUI, and get a terminal app.

@Metadata {
    @DisplayName("TUI")
    @PageImage(purpose: icon, source: "tuikit-logo", alt: "TUI Logo")
    @PageImage(purpose: card, source: "tuikit-logo", alt: "TUI Logo")
}

## Overview

TUI speaks SwiftUI's language: views, `@State`, `@Observable`, stacks, lists, tables, navigation, sheets, menus, animation and much more. It draws them with nothing but Swift and the terminal's own escape codes, on macOS, on Linux, and in a web browser.

```swift
import TUI

@main
struct Hello: App {
    var body: some Scene {
        WindowGroup {
            VStack {
                Text("Hello, TUI!").bold()
                Button("Press me") {}
            }
        }
    }
}
```

Everything works from the keyboard (<doc:FocusSystem>), and a person running your app can ask for less motion, more contrast or cues that don't rest on colour, which TUI's own controls follow (<doc:EnvironmentVariables>). Apps can post notifications (<doc:Presentation#Notifications>), keep settings in a ``Settings`` scene, and bring each terminal window back where it was with ``SceneStorage``.

[See TUI in action](https://swift-tui.com/), or [try the demo in your browser](https://swift-tui.com/demo/).

## Topics

### Get Started

- <doc:GettingStarted>
- <doc:BuildingYourFirstApp>
- <doc:ComingFromSwiftUI>
- <doc:ChoosingProducts>
- <doc:Troubleshooting>

### Test Your App

- <doc:TestingYourApp>

### Build Your Interface

- <doc:ViewsAndText>
- <doc:Controls>
- <doc:LayoutAndGeometry>
- <doc:ListsAndTables>
- <doc:ScrollingContent>

### Structure Your App

- <doc:AppsAndWindows>
- <doc:NavigationAndPresentation>
- <doc:StateAndData>

### Respond and Move

- <doc:KeyboardMouseAndFocus>
- <doc:AnimationAndEffects>

### Style It

- <doc:ColorsAndThemes>
- <doc:ControlStyles>

### Go Deeper

- <doc:KeepingYourAppFast>
- <doc:UnderTheHood>
