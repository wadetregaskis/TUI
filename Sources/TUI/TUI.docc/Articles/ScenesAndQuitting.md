# Scenes, Phases and Quitting

Say what your app shows, notice when it is suspended or loses focus, end it cleanly, and decide what it does with no terminal.

## Overview

An app is a type that conforms to ``App``, marked `@main`. Its `body` lists the app's scenes, and each scene holds
views:

```swift
import TUI

@main
struct Notes: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

struct ContentView: View {
    var body: some View {
        Text("Hello, TUI!")
    }
}
```

TUI does the rest. It takes over the terminal when the app starts, draws the scene whenever something changes, and
hands the terminal back as it found it when the app ends. Most apps need nothing more than this.

## Scenes

``WindowGroup`` is the scene almost every app starts with: its content fills the terminal.

A terminal shows one surface, so any other scene appears over the first when something asks for it:

| Scene | What it is | How it opens |
|---|---|---|
| ``Window`` | A second screen, by its identifier | ``EnvironmentValues/openWindow`` |
| ``Settings`` | The app's settings, as a sheet | ``EnvironmentValues/openSettings`` |

```swift
@main
struct Notes: App {
    var body: some Scene {
        WindowGroup { ContentView() }
        Window("Connection Doctor", id: "doctor") { DoctorView() }
    }
}

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Check the connection") { openWindow(id: "doctor") }
    }
}

struct DoctorView: View {
    var body: some View { Text("All good") }
}
```

## Knowing the Scene's Phase

Read `scenePhase` from the environment to learn what the scene is doing, and use `onChange(of:)` to act when it
changes:

```swift
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Text("Notes")
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { reloadFromDisk() }
            }
    }

    func reloadFromDisk() {}
}
```

| Phase | What it means in a terminal | Can you rely on it? |
|---|---|---|
| ``ScenePhase/active`` | The app is running and taking input | Yes |
| ``ScenePhase/inactive`` | The terminal window, tab or pane lost focus | No: many terminals never say |
| ``ScenePhase/background`` | The app is suspended, and the shell has the terminal | Yes |

Coming back from ``ScenePhase/background`` is a good moment to look at files again, because anything may have
changed while the app was stopped.

Treat ``ScenePhase/inactive`` as a hint, and build nothing that depends on it. An app that loses focus stays on
screen, so spinners and progress bars go on animating. To draw your own view differently while it is inactive, read
``EnvironmentValues/appearsActive`` rather than the phase. ``ScenePhase`` has the details.

## Quitting

A person can quit your app from the keyboard: Control-Q quits, and Control-\\ asks first.
<doc:KeyboardShortcuts#Quitting> says what each does, how to change them, and how to keep them from working on some
screens.

If quitting now would lose something, say so, and every key asks first and names it:

```swift
struct UploadsView: View {
    let isUploading: Bool

    var body: some View {
        Text("Photos")
            .quitWarning("Uploading 6 photos", isActive: isUploading)
    }
}
```

Only a view that's drawn can warn, so put a warning for work that goes on behind every screen at the root of the
scene. To choose when quitting asks, set `.quitConfirmation` on the scene. `.always` asks for every quit, and `.whenWarned`
only with a warning active, so Control-\\ then quits at once:

```swift
@main
struct Notes: App {
    var body: some Scene {
        WindowGroup { ContentView() }
            .quitConfirmation(.always)
    }
}
```

To quit from your own code, call `dismiss` from the environment:

```swift
struct ContentView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button("Quit") { dismiss() }
    }
}
```

The same call does what you would expect wherever you write it. Inside a sheet, an alert or a pushed navigation
screen, it closes that and leaves the app running. It quits only where nothing encloses the view, without asking,
because your code has decided. The terminal is then restored, and `main()` returns.

> Tip: Prefer `dismiss()` to `exit(0)`. TUI still restores the terminal after `exit(0)`, but the rest of the shutdown
> does not run, so a setting stored a moment before may not reach the disk.

## Running Without a Terminal

An app needs a terminal to draw on. If stdout or stdin isn't one, as in `myapp > out.txt`, `myapp | grep x`,
`myapp < /dev/null` or a CI step, or if `TERM` is `dumb`, the app prints one line to stderr saying so and exits with status
1. No escape codes go down the pipe.

Where running that way makes sense for your app, implement ``App/runWithoutTerminal(_:)``. It's called in place of the
interface, and is told what's missing and why (``NoTerminal``). Return an exit status:

```swift
@main
struct Inventory: App {
    var body: some Scene { WindowGroup { Text("Stock") } }

    static func runWithoutTerminal(_ situation: NoTerminal) async -> NoTerminal.Outcome {
        // `inventory > stock.txt` gets the same data, as a report.
        guard situation.lacksOutput else { return situation.reportFailure() }
        renderOnce { Text("12 apples") }
        return 0
    }
}
```

``renderOnce(output:content:)`` draws a view once from the line the cursor is on, and works with or without an ``App``.
When stdout isn't a terminal it writes plain text, unless you pass `output: .escapeSequences` or whoever runs the program
sets `TUI_FORCE_ESCAPES=1` or `FORCE_COLOR=1`.

A tool like `fzf`, which reads its data from a pipe and draws on the terminal anyway, returns
``NoTerminal/Outcome/drawOnControllingTerminal``. The app then runs as usual on the process's controlling terminal, and
the pipes stay reachable as ``NoTerminal/pipedInput`` and ``NoTerminal/pipedOutput``. Read and write those rather than
using `readLine()` or `print`, which now reach the terminal.

## See Also

- <doc:KeyboardShortcuts>
- <doc:ShippingAnApp>
- <doc:AppLifecycle>
