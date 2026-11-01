# Scenes, Phases and Quitting

Say what your app shows, notice when it is suspended or loses focus, and end it cleanly.

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

A person can quit your app from the keyboard. <doc:KeyboardShortcuts> says which keys do it, how to change them, and
how to keep them from working on some screens.

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
screen, it closes that and leaves the app running. It quits only where nothing encloses the view. The terminal is
then restored, and `main()` returns.

> Tip: Prefer `dismiss()` to `exit(0)`. TUI still restores the terminal after `exit(0)`, but the rest of the shutdown
> does not run, so a setting stored a moment before may not reach the disk.

## See Also

- <doc:KeyboardShortcuts>
- <doc:ShippingAnApp>
- <doc:AppLifecycle>
