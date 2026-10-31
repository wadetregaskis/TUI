# Coming from SwiftUI

The differences you should know about when you already know SwiftUI.

## Overview

Most SwiftUI code compiles under TUI and does what you expect. The differences come from what a terminal is: a grid of character cells, in one font, reached through a keyboard and sometimes a mouse.

Two rules help when something surprises you:

- **If TUI can't do what you asked, your code usually doesn't compile.** It rarely accepts a request and quietly ignores it. So a compile error usually means "this has no meaning in a terminal", and this page tells you what to use instead. The one exception you're likely to meet is `ObservableObject`, below.
- **If it compiles but behaves differently, it's probably listed here.** This page covers the differences you're most likely to meet, not every one.

## Sizes are in character cells

Every size, position and distance is a whole number of cells, not points. One column is roughly as wide as 8 points, and one row as tall as 16, so numbers copied from SwiftUI come out far too big.

```swift
// SwiftUI
VStack(spacing: 8) { ... }
    .padding(20)
    .frame(width: 300)

// TUI
VStack(spacing: 1) { ... }
    .padding(1)
    .frame(width: 40)
```

- These all take `Int`, so a fractional value such as `width / 2.5` doesn't compile.
- Geometry uses `CellPoint`, `CellSize` and `CellRect` rather than `CGPoint`, `CGSize` and `CGRect`. You'll see them from `GeometryReader`, gestures and custom layouts. `CellRect` has no `midX` or `midY`.
- Gesture distances are cells too: `DragGesture(minimumDistance: 10)` waits for the mouse to move ten cells. The default of one cell is usually what you want.
- Default spacing is tight. `VStack` puts no blank row between its views, `HStack` puts one column, and `.padding()` is one cell on each side.

## A fixed frame aligns to the top left

A frame with a fixed size puts its content at the top left, where SwiftUI centres it. Fixed widths in a terminal are nearly always columns of text, which you want lined up on the left.

```swift
Text("Name").frame(width: 20)                       // at the left of the 20 columns
Text("Name").frame(width: 20, alignment: .center)   // centred, as in SwiftUI
```

A flexible frame, such as `.frame(maxWidth: .infinity)`, still centres. `VStackLayout`, `HStackLayout` and `ZStackLayout` also default to the top left, unlike `VStack`, `HStack` and `ZStack`, which centre as they do in SwiftUI.

## There is one font, in one size

A terminal draws everything in one font and size, so text styles change how strong the text looks instead.

```swift
Text("Heading").font(.title)        // bold, not larger
Text("Body").font(.body)            // normal
Text("Details").font(.caption)      // faint, not smaller
```

`largeTitle` through `headline` are bold, and `footnote`, `caption` and `caption2` are faint. `Font.system(size:)` doesn't compile. Nor do the font designs `.serif` and `.rounded`, because the terminal chooses the font.

## Use `@Observable`, not `ObservableObject`

TUI watches only the Observation framework, so use `@Observable` for a model.

- `@StateObject`, `@ObservedObject`, `@EnvironmentObject` and `.onReceive(_:perform:)` don't compile.
- `ObservableObject` and `@Published` do compile on macOS, because Foundation brings them in, but TUI doesn't watch them. Writing to a `@Published` property doesn't redraw anything, and nothing tells you so. Check for this first if you've moved a model over from SwiftUI and the screen doesn't update.

```swift
// SwiftUI, the older way
class Model: ObservableObject { @Published var count = 0 }
@StateObject var model = Model()

// TUI, and modern SwiftUI
@Observable class Model { var count = 0 }
@State var model = Model()
```

Pass a model with `.environment(model)` and read it with `@Environment(Model.self)`, in place of `@EnvironmentObject`.

## The ⌘ key becomes Control

Most terminals don't tell an app about ⌘, and they keep shortcuts like ⌘C and ⌘V for themselves. So a shortcut written for ⌘ answers to Control instead, on every terminal.

```swift
Button("Save") { save() }
    .keyboardShortcut("s")      // Control-S
```

- To use something else, write `.commandKey(.option)`, or `.commandKey(.bare)` for the key on its own.
- To also answer to a real ⌘ where the terminal passes it on, write `.keyboardShortcutsMatchCommand()`.
- The Shift modifier is only reported for uppercase letters. `A` has Shift, but `!` and `+` don't, so match those by their character.

## Something always has the keyboard

A terminal app has to be usable without a mouse, so the first control on a screen or in a new sheet takes the focus by itself. If you state a preference with `.defaultFocus`, or move the focus with `@FocusState`, that takes over.

A link inside a `Text` is a control like any other. The Tab key stops on it, Return opens it, and it's underlined so that you can see it's a link. To remove the underline, write `.linkUnderline(false)`.

## Lists keep a cursor apart from the selection

In a `List` or `Table`, the arrow keys move a cursor, and Space or Return selects the row under it. On a Mac, moving is selecting. If your code reacts to selection changes, it won't run as the user arrows through the rows.

- A click on the selected row clears a single selection, so there's always a way back to nothing selected.
- With a multiple selection, Control-click or Option-click toggles a row, in place of ⌘-click. Control-click opens the row's menu instead if it has one.
- A `Table` row is one line tall, even if a cell has more to show. Allow more with the column's `lineLimit(_:)`, or let rows grow with `.tableRowHeights(.automatic)`.

## Long content belongs in a `List`

A `LazyVStack` draws only the rows it can show, but it doesn't save as much as it does in SwiftUI: rows that scroll away stay in the view tree, and a lazy stack nested inside other scrolling content draws everything. For a lot of data, use `List`, which is built for it.

Because of this, a row that scrolls away **keeps its `@State`**, where SwiftUI would eventually discard it. A collapsed `DisclosureGroup` keeps its content's state too. `onAppear` and `task` still run when a row comes into view, so don't use a reset of `@State` to notice a row coming back.

## Animation moves in whole cells

`withAnimation`, springs, transitions and `Animatable` all work, but nothing can be drawn between two cells, so a view moves in steps of a cell. Fades and colour changes are smooth. A few things differ from SwiftUI:

- **Text doesn't cross-fade.** A `Text` whose string changes under an animation changes at once. To get a dissolve, ask for it:

  ```swift
  Text(status)
      .contentTransition(.opacity)
  ```

- **Sizes jump.** A view that changes size takes its new size at once. Its position can glide, but only among the children of `VStack`, `HStack`, `ZStack` and a custom `Layout`.
- **Removals can be abrupt.** With no `.transition` of its own, a row or `switch` case that goes away goes at once, though one coming in fades in. Write a `.transition` to control how it leaves.
- **One animation per frame.** A frame draws every change made since the last one under one animation. So if you change one value plainly and another inside `withAnimation` at the same moment, both animate.

## Scrolling moves line by line

Scrolling moves whole rows and columns, with no momentum or bounce. An animated `scrollTo` still glides, a line at a time.

A scroll bar takes up a column of the view and is drawn whenever the content overflows, instead of floating over the content and fading away. So the content has one column less to work with. Hide it with `.scrollIndicators(.hidden)`.

## Pictures depend on the terminal

An `Image` is drawn in real pixels where the terminal supports the Kitty graphics protocol, and as text characters everywhere else.

- `Image(systemName:)` draws nothing unless the terminal's font has that symbol, so don't rely on SF Symbols for anything essential.
- An image made from a `CGImage` or `NSImage` is read once. Drawing into it later won't change what's on screen.
- An image that isn't `.resizable()` draws at its natural size only where TUI knows how big a cell is: Apple's Terminal, Warp, iTerm2, and Ghostty on its own Mac. Elsewhere it fits the space it's offered.

## Shapes and materials are made of cells

Shapes work, within the limits of the grid.

- `Rectangle`, `RoundedRectangle` and `Capsule`, when stroked, draw as a box of line characters. A corner is either square or round, whatever radius you ask for.
- Materials really do frost what's behind them, but they do it cell by cell, and the text underneath is dropped rather than blurred.

## Windows fill the terminal

A terminal has one surface, so app structure changes a little.

- **One window at a time.** `openWindow` opens a window over the whole terminal, and only the front one is drawn or gets input. The ones behind keep running, and come back when it closes.
- **Closing the last window quits the app**, whether by `dismissWindow` or by `dismiss()` at the window's root. Escape closes a window only while another is open behind it.
- **Toolbars are bars.** `.toolbar` items go into one bar above the page or one below it, each drawn only when it has something in it. `.principal` replaces the title, and `.status` goes in the bottom bar.
- **Sheets fit their content.** There's no minimum size.
- **Help appears in the status bar.** `.help("…")` shows there when the mouse rests on a view, or when the user presses `?` on a focused control. For a panel beside the view, write `.tooltipStyle(.popover)`.
- **File panels are TUI's own.** `fileImporter` and its relatives draw a panel in the terminal, browsing the machine the app is running on. Over `ssh`, that's the remote machine, not the one in front of the user.

## Colours and appearance are set differently

You can read `\.colorScheme`, and set it with `.environment(\.colorScheme, .dark)`, as in SwiftUI. In place of `.preferredColorScheme(_:)`, set the look of your app directly:

```swift
ContentView()
    .palette(SystemPalette(.blue))      // the colours
    .appearance(.rounded)               // borders and figures
    .controlStyle(.lines)               // how controls are drawn
```

`.tint` works as it does in SwiftUI.

## Things that don't exist

These have no meaning in a grid of cells, or aren't built yet, so using them is a compile error:

| In SwiftUI | In TUI |
|---|---|
| `.scaleEffect`, `.rotationEffect`, `.rotation3DEffect` | None. A cell can't be scaled or rotated. |
| `.blur` | None. For a frosted look, use a material. |
| `.preferredColorScheme` | `.palette` and `.appearance`. |
| `@StateObject`, `@ObservedObject`, `@EnvironmentObject` | `@Observable` with `@State`, `@Bindable` and `@Environment`. |
| `.onReceive` | A `.task`, or an `@Observable` model. |
| `Font.system(size:)`, the font designs `.serif` and `.rounded` | `.font(.title)` and the other text styles. |
| Right-to-left layout | Not yet. `\.layoutDirection` is always left to right and can't be set. |
| VoiceOver and accessibility traits | None. |
| `.foregroundColor` | `.foregroundStyle`. |
| `.cornerRadius` | `.background(.blue, in: RoundedRectangle(cornerRadius: 1))`, or `.clipShape(RoundedRectangle(cornerRadius: 1))`. |
| `NavigationView` | `NavigationStack`, or `NavigationSplitView` for columns. |
| `.tabItem` | `Tab("Inbox", systemImage: "tray") { … }` inside the `TabView`. |
| `.imageScale` | None. Leave it out: a symbol is one glyph of the terminal's font. |
| `.ignoresSafeArea` | None. Leave it out: a terminal has no safe area, and your views already reach its edges. |
| `ShareLink` | None. A terminal has no share sheet. To open something, use `Link`. |
| `DocumentGroup` | A `WindowGroup`, with `.fileImporter` and `.fileExporter`. |
| `.onOpenURL` | None. Nothing sends a terminal app a URL. Read `CommandLine.arguments` at launch. |
| `.defaultSize`, `.windowResizability` | None. Leave them out: a window is the size of the terminal. |
| `@Entry` | Add `import TUIMacros`, and the `TUIMacros` product to your target (<doc:ChoosingProducts>). It's a product of its own because it builds swift-syntax. |
| `.background(view)`, `.overlay(view)` | `.background { view }`, `.overlay { view }`. `.overlay(.red)` and `.background(.red)` take a style as they do in SwiftUI. |

## Sharing code with a SwiftUI app

The aim is to learn once and write anywhere, not to write once and run anywhere, but a lot of view code can be shared. Choose the framework with a conditional import, and give sizes names, since the same number means something different on each side:

```swift
#if canImport(TUI)
    import TUI
    let gap = 1
#else
    import SwiftUI
    let gap: CGFloat = 8
#endif

struct Row: View {
    var body: some View {
        HStack(spacing: gap) {
            Text("Name")
            Spacer()
            Text("Value")
        }
    }
}
```

## See Also

- <doc:GettingStarted>
- <doc:LayoutSystem>
- <doc:KeyboardShortcuts>
- <doc:ListAndTable>
- <doc:AnimatingChanges>
