# Testing Your App

Run your views in a unit test: press keys, click, move a clock by hand, and read the screen.

## Overview

Here is a view and a complete test of it:

```swift
import Testing
import TUI
import TUITesting

struct Counter: View {
    @State private var count = 0

    var body: some View {
        VStack {
            Text("Count: \(count)")
            Button("Add") { count += 1 }
        }
    }
}

@MainActor
@Test func addCounts() {
    let app = TestApp(width: 40, height: 10) { Counter() }
    #expect(app.screen.contains("Count: 0"))

    app.press(.space)

    #expect(app.screen.contains("Count: 1"))
}
```

To run it, add the `TUITesting` product to your test target, and nothing else needs to change. Your app's own target
does not depend on it, so a shipping app carries none of it:

```swift
.testTarget(
    name: "MyAppTests",
    dependencies: [
        "MyApp",
        .product(name: "TUITesting", package: "TUI"),
    ]
)
```

``TestApp`` runs what a running app runs: the render loop, the focus system and the input chain. `@State` lasts from
frame to frame, `.onAppear` and `.task` run, a key goes to the control with the focus, and a click goes to whatever
the last frame drew at that cell. Only the terminal is missing, so a test needs none, and runs on macOS and Linux.

`TestApp` must be used on the main actor, so mark your test or its suite `@MainActor`. It works the same way in XCTest
and Swift Testing, and depends on neither. You don't need `@testable` for your tests to use it, only if your own code
needs it. The rest of this page shows each thing it does.

### Running a view or an app

Give it a view, as above, or your whole app:

```swift
let app = TestApp(MyApp(), width: 100, height: 30)
```

A view starts at the top-left corner of the screen, so its first row is `lines[0]`. A whole app is laid out as in a
terminal, its bars included, and a `WindowGroup` centres what is smaller than the window.

The first frame is drawn the first time you read the screen or act, and every action draws the frames it causes before
it returns. There is nothing to flush and nothing to wait for, unless the work is your own: see
<doc:TestingYourApp#Work-that-takes-real-time>.

An `@AppStorage` with no store of its own uses one in memory, which belongs to that `TestApp`. A test leaves nothing in
your preferences, and one test's settings are not the next one's.

### Reading the screen

``TestApp/screen`` is a ``TestScreen``, a value holding what is on screen at that moment. A failing `#expect` on it
prints the whole screen.

```swift
app.screen.contains("Count: 1")      // Whether it shows anywhere, all on one row.
app.screen.lines[0]                  // One row, as plain text with no trailing spaces.
app.screen.line(containing: "Count") // The first row that shows it.
app.screen.text                      // All of it, for comparing the whole.
app.screen.location(of: "Add")       // The cell it starts at, as a CellPoint.
app.screen.locations(of: "Add")      // Every place it shows.
app.screen.styledLines               // The rows with their escape codes.
```

To ask what has the keyboard focus, read ``TestApp/focusedID``. Name the controls you care about with `.focusID(_:)`:

```swift
Button("Add") { count += 1 }.focusID("add")
```

```swift
#expect(app.focusedID == "add")
```

### Pressing keys and typing

```swift
app.press(.down)
app.press(.tab, modifiers: .shift)
app.press(.down, times: 3)
app.press(.character("k"), modifiers: .control)
app.type("Ada Lovelace")
```

A key goes where a keypress goes: to the control with the focus, then what holds it, then the app's shortcuts.
``TestApp/press(_:modifiers:times:)`` returns whether anything took the key.

A shortcut declared the SwiftUI way, like `.keyboardShortcut("s")`, is a ⌘ shortcut, which fires in a terminal on the
key standing in for ⌘. That's Control unless your app says otherwise with `.commandKey(_:)`, so press it with
`modifiers: .control`.

To paste, press ``Key/paste(_:)``: `app.press(.paste("copied text"))`.

### Clicking, scrolling and dragging

Name what you mean by the text on screen, or give a cell:

```swift
try app.click("Save")
try app.click("Item", button: .right)
try app.hover(over: "Help")
try app.scroll(.down, by: 3, over: "Inbox")
try app.drag(from: "Report.pdf", to: "Archive")

app.click(at: CellPoint(x: 4, y: 0))
app.scroll(.down, by: 3)
```

The forms that take text throw when the screen does not show it. Mark the test `throws`, and it fails on that line with
a message that shows the screen. A click lands on the middle of the text. When the text shows more than once, the
first place is used, reading from the top: find the one you mean with ``TestScreen/locations(of:)`` and use the form
that takes a cell.

A click is a press, a frame, a release and a frame. Two clicks in one place with no time between them are a double
click, as they would be for a person. To make them two clicks, move the clock between them.

As in a terminal, the pointer's moves arrive only if the app has asked to hear of them, which `.onHover`,
`.onContinuousHover` and `.help` do.

### Moving time

The clock stands still until you move it, so nothing depends on how fast the machine is:

```swift
Button("Open") {
    withAnimation(.linear(duration: 1)) { isOpen = true }
}
```

```swift
app.press(.enter)
app.advance(by: .milliseconds(500))    // Half way through the animation.
app.advance(by: .milliseconds(500))    // Finished.
```

``TestApp/advance(by:)`` draws every frame the app asks for on the way, as a running app would, and takes no real time
beyond drawing them. A second of animation is sixty frames; an hour with nothing animating is one. Animations and
transitions move on this clock, as do a `TimelineView`, a long press, a tooltip's delay and a blinking cursor.

A `TimelineView` shows ``TestApp/date``, which you can set for a test of a particular day. ``TestApp/elapsed`` is how
much time has passed.

### Work that takes real time

Your own async work runs on its own time, and a task on the main actor only gets its turn when the test suspends. So
make the test `async`, and wait for what the work does:

```swift
struct Loader: View {
    @State private var name = "…"

    var body: some View {
        Text("Hello, \(name)").task { name = await loadName() }
    }
}

@MainActor
@Test func loadsTheName() async throws {
    let app = TestApp { Loader() }
    try await app.wait(for: "Hello, Ada")
}
```

``TestApp/wait(for:timeout:)`` returns as soon as the screen shows the text. ``TestApp/wait(until:timeout:)`` waits for a
condition of your own. The timeout only ends a test that would otherwise hang, so it is long, and a test that passes
takes only as long as the work does.

A `Task.sleep` in a `.task` sleeps on the machine's clock, and ``TestApp/advance(by:)`` cannot hurry it. If a test should
not have to wait through it, have the view sleep on a clock it is given, the real one in your app and a
``TestClock`` in the test:

```swift
struct Ticker<C: Clock<Duration>>: View {
    let clock: C
    @State private var ticks = 0

    var body: some View {
        Text("Ticks: \(ticks)").task {
            while (try? await clock.sleep(for: .seconds(1))) != nil { ticks += 1 }
        }
    }
}

@MainActor
@Test func ticks() async throws {
    let clock = TestClock()
    let app = TestApp { Ticker(clock: clock) }
    try await app.wait(until: { clock.sleepers == 1 })

    clock.advance(by: .seconds(1))

    try await app.wait(for: "Ticks: 1")
}
```

A view's tasks are cancelled when its `TestApp` goes away, so a loop like that one does not run on into the next test.

### Comparing with a stored snapshot

A long screen can be easier to check by eye once, and then compare from then on:

```swift
try app.screen.compareToSnapshot("settings-page")
```

The snapshot is the screen's text, in `__Snapshots__/settings-page.txt` beside the test's source file, for you to commit.
The first run writes it and throws, so that you look at it. When a change is what you meant, run the tests with
`TUI_RECORD_SNAPSHOTS=1` in the environment to write them again. It holds wording and layout, not colour.

### What it does not do

- **It doesn't check what a terminal does with the output.** The screen is what TUI built for the terminal, row by row.
  A glyph a particular terminal draws too wide, or a key it doesn't send, won't show here.
- **It doesn't draw pictures.** An image sent with a terminal's graphics protocol isn't text on the screen.
- **Some terminal input is out of reach.** ``TestApp/press(_:times:)`` takes any ``KeyEvent``, but the chords a test can
  send aren't all ones a real terminal can: a legacy terminal sends no ⌘ chord, and most report few modifiers on a
  function key.
- **A few timers read the machine's clock.** A wheel's grace at the end of a scroll, and the repeat of a held key, use
  real time.
- **A view's own reading of the clock is real.** `Date()` in a `body` reads the machine's clock, not ``TestApp/date``.
- **A view notices a change the way it does in your app.** Make it through `@State` or an `@Observable` model. A plain
  variable that the content closure reads can go unnoticed by a part of the screen TUI has kept from an earlier frame.
- **It runs one thing at a time.** ``TestApp`` is on the main actor, and tests of it run side by side only as your other
  main-actor tests do.
- **It needs `TUIApp`,** so it has no Windows build, where TUI's console layer has none yet.
- **Colours are in the escape codes.** ``TestScreen/styledLines`` has them, but TUI has no API for asking what colour a
  cell is. To test that something changes colour, compare rows of `styledLines`.

## Topics

### Running

- ``TestApp``
- ``TestScreen``
- ``TestClock``
- ``TestAppError``
