# State Management

Manage reactive state in your TUI application.

## Overview

State works as it does in SwiftUI. When a value changes, TUI draws the views that depend on it again. `@State` holds a view's own values, `@Observable` holds data that views share, and a binding lets a control edit a value that lives somewhere else.

## @State

Use ``State`` for simple values owned by a single view:

```swift
struct CounterView: View {
    @State var count = 0

    var body: some View {
        VStack {
            Text("Count: \(count)")
            Button("Increment") {
                count += 1  // Triggers re-render
            }
        }
    }
}
```

## @Observable

When several views share data, or the data has some logic of its own, put it in a class marked `@Observable`. Hold it in a `@State` property in the view that owns it:

```swift
@Observable
final class Library {
    var books: [String] = []
}

struct LibraryView: View {
    @State private var library = Library()

    var body: some View {
        VStack {
            Text("\(library.books.count) books")
            Button("Add a Book") {
                library.books.append("Untitled")
            }
        }
    }
}
```

A view that reads a property is drawn again when that property changes, and that includes a write made from a `.task`.

To hand the model to views further down, pass it as an ordinary value or put it in the environment:

```swift
struct LibraryScreen: View {
    @State private var library = Library()

    var body: some View {
        ShelfView()
            .environment(library)
    }
}

struct ShelfView: View {
    @Environment(Library.self) private var library

    var body: some View {
        Text("\(library.books.count) books")
    }
}
```

To get a binding to one of its properties, for a control to edit, use ``Bindable``:

```swift
@Observable
final class Profile {
    var name = ""
}

struct ProfileForm: View {
    @Bindable var profile: Profile

    var body: some View {
        TextField("Name", text: $profile.name)
    }
}
```

> Note: TUI watches only `@Observable`. `ObservableObject` and `@Published` compile on macOS, but a write to one doesn't redraw anything. See <doc:ComingFromSwiftUI>.

## Binding

``Binding`` provides a two-way connection to a value owned elsewhere. Use the `$` prefix on a `@State` property to get its binding:

```swift
struct ParentView: View {
    @State var selection = "medium"

    var body: some View {
        Picker("Size", selection: $selection) {
            Text("Small").tag("small")
            Text("Medium").tag("medium")
            Text("Large").tag("large")
        }
    }
}
```

Create constant bindings for previews or static values:

```swift
let binding = Binding.constant(42)
```

### Binding to something that might not be there

`$model.field` derives a binding to any property, including an optional one —
and a dictionary entry derives the same way, because a key that isn't there has
no value:

```swift
@State private var enabled: [String: Bool] = [:]

var body: some View {
    ForEach(features, id: \.self) { feature in
        Toggle(feature, isOn: $enabled[feature].defaulted(to: false))
    }
}
```

`$enabled[feature]` is a `Binding<Bool?>`, which ``Toggle`` cannot take: it has
to draw a checkbox one way or the other, and "absent" is not a third way to draw
it. `defaulted(to:)` decides which way absent means, at the call site where the
answer is known.

Writing through such a binding **creates** the entry — including a write of the
fallback itself, so a feature toggled on and then off leaves `[feature: false]`
rather than nothing. That is usually what "which of these are chosen" wants; a
collection that should hold *only* what was chosen is better modelled as a `Set`.

`defaulted(to:)` is TUI-only. The portable spelling is the longhand it saves:
`Binding(get: { enabled[feature] ?? false }, set: { enabled[feature] = $0 })`.

## @Environment

``EnvironmentValues`` provides values propagated down the view hierarchy:

```swift
struct MyView: View {
    @Environment(\.palette) var palette
    @Environment(\.statusBar) var statusBar

    var body: some View {
        Text("Themed text")
            .foregroundStyle(palette.foreground)
    }
}
```

### Defining Custom Environment Keys

```swift
struct MyCustomKey: EnvironmentKey {
    static let defaultValue = "default"
}

extension EnvironmentValues {
    var myCustomValue: String {
        get { self[MyCustomKey.self] }
        set { self[MyCustomKey.self] = newValue }
    }
}
```

SwiftUI's shorthand, the `@Entry` macro, writes the key for you. It's in the
`TUIMacros` product, which you add to your target and import beside TUI
(<doc:ChoosingProducts>):

```swift
import TUIMacros

extension EnvironmentValues {
    @Entry var myCustomValue = "default"
}
```

Inject values with the `.environment()` modifier:

```swift
ContentView()
    .environment(\.myCustomValue, "custom")
```

## @AppStorage

``AppStorage`` keeps values across app launches, in `UserDefaults` on Apple platforms and in a JSON file elsewhere:

```swift
struct SettingsView: View {
    @AppStorage("username") var username = "Guest"

    var body: some View {
        Text("Hello, \(username)!")
    }
}
```

### What a write redraws

A view that read a stored value — in its `body`, or through a control bound to
`$username` — is redrawn when the value changes, and nothing else is: a write is
observed like a change to an `@Observable` property, through the key's
``StoredKey``. That holds for a write made through the store itself
(`StorageDefaults.backend.setValue(_:forKey:)`) as much as for one through the
wrapper.

### Which store

A property that names a store — `@AppStorage("key", store: …)` — uses it. One
that names none uses the store `defaultAppStorage(_:)` set nearest above its
view, on the view or on its scene, and ``StorageDefaults/backend`` where none
is set:

```swift
WindowGroup {
    ContentView()
}
.defaultAppStorage(UserDefaults(suiteName: "group.example.shared")!)
```

On Apple platforms both take a `UserDefaults`, as SwiftUI's do, and on every
platform a ``StorageBackend``. The store is found where the view is drawn,
before its `body` runs, so a closure the body made — a button's action — writes
to the store the body read. Give it a store that lives as long as the view: one
made afresh in `body` is correct, but a new store each time redraws the subtree
beneath it.

### Your own store

Any ``StorageBackend`` can stand behind `@AppStorage(_:store:)`. A store implements
four primitives — read an entry, store, remove, synchronize — and hands back the
key's ``StoredKey`` from each, the same one every time; the methods everyone else
calls (`value(forKey:)`, `setValue(_:forKey:)`, `removeValue(forKey:)`) do the
observation around them. Keep each key's `StoredKey` beside its value, so a read
— which is on the render path — finds both in one lookup.

### When a save fails

SwiftUI's `@AppStorage` is backed by `UserDefaults`, which for practical purposes
cannot fail. Ours falls back to a JSON file off Apple platforms — and a file in a
user-owned directory genuinely can fail to write: read-only mount, full disk, a
sandbox that denies the path.

The wrapper's signature is SwiftUI's, so its setter cannot throw. The failure
surfaces beside the API instead, through ``StorageDiagnostics``:

```swift
StorageDiagnostics.onFailure = { failure in
    Task { @MainActor in showBanner("Couldn't save settings: \(failure)") }
}
```

With no handler installed the failure is still recorded rather than dropped —
``StorageDiagnostics/lastFailure`` and ``StorageDiagnostics/failureCount`` always
reflect what happened, so an app can check after a `synchronize()`.

Reads are deliberately quieter: a value that fails to *decode* falls back to the
declared default, which is defined behaviour and sits on the per-frame render
path. Directory creation, loads, encodes and writes are all reported.

## @SceneStorage

``SceneStorage`` keeps where the user was, such as a tab, a selection or a scroll position, rather than what they
chose. It is kept per window: each window the app opens has values of its own, and `@SceneStorage("tab")` is never the
same value as `@AppStorage("tab")`.

```swift
struct BrowserView: View {
    @SceneStorage("selectedTab") private var selectedTab = "inbox"
    // …
}
```

A terminal app's nearest thing to a window is the terminal window, tab or pane it runs in, so each value is also kept
per terminal session. A write goes to the session's copy and to a copy shared by every session, the last saved. A read
takes the session's copy, else the last saved, else the default. So:

- Run the app again in the same terminal window and it's back where it was in that window.
- Run it in two windows at once and each keeps its own place.
- Open a new window, as someone who opens one for each task does, and it starts from wherever they last left it.

The session is what the terminal names in the environment it started the shell with: a tmux pane, a screen window,
`TERM_SESSION_ID` (Apple Terminal), `ITERM_SESSION_ID` (iTerm2), `KITTY_WINDOW_ID`, `WEZTERM_PANE`, `WT_SESSION`
(Windows Terminal) and the like. Where there's none, as over a plain ssh connection or in Ghostty, which names no window,
there is only the last saved. A store keeps each session for 30 days after its last write, however many there are.

It is stored where an `@AppStorage` with the same `store:`, or none, would be: <doc:StateManagement#Which-store>
applies as it stands.

## Where Saved State Lives

A terminal app often runs on one machine while the person using it sits at another, at the far end of an ssh
connection. TUI decides each kind of state by whose it is.

**On the machine the app runs on**, as SwiftUI keeps it on the machine it runs on:

- `@AppStorage` and `@SceneStorage` values, in `UserDefaults` on macOS and in `settings.json` in the app's configuration
  directory elsewhere (`TUI_CONFIG_DIR` moves it).
- The language chosen in the app, in the same directory.
- A toolbar's customization, and a file panel's view mode, last folder and size.
- Documents, and whatever a file panel opens, saves or creates.
- Pictures downloaded for an `Image` or an `AsyncImage`, which go through `URLSession.shared` and so through Foundation's
  shared `URLCache`, which Foundation may keep on disk.

That is the right place for them: they describe the app and the files it works on, and over ssh those files are on the
app's machine. A file panel that opens over ssh says so.

**With the person**, where they are, wherever the app runs:

- The clipboard, the system notifications, and the host's accessibility settings (Reduce Motion and the like) and
  spring-loading delay. TUI uses the host's only where it can tell the person is at the machine the app runs on: not
  over ssh or mosh, in tmux only when every attached client is local, and not in a session keeper that can't say who
  is attached, such as screen. Elsewhere it uses what the terminal offers: OSC 52 for the
  clipboard, the terminal's own notifications, and the `TUI_` environment variables for the settings.
- A language saved in the app beats `LANG`. ssh forwards `LANG` from the person's machine, which is a good guess, but a
  choice made in the app is a choice, and it stays made from any machine.

**Never saved:** anything TUI measures about a terminal, such as character widths, capabilities, quirks and colours. It
is measured again at each launch, because the next launch may be from another terminal. If such a measurement is ever
cached, key it by the terminal's fingerprint (its answers to the device-attribute queries, and its version), never by
its name in `TERM_PROGRAM`: several people, or one person's several terminals, can share one account and one name.

## How Long State Lasts

A view's `body` runs many times, but its `@State` isn't reset each time. The value lasts for as long as the view stays in the tree, wherever the tree puts it:

- The two sides of an `if`/`else` or the cases of a `switch` are different views, each with state of its own. Switching to the other side and back starts the first one afresh.
- A view that leaves the tree loses its state, unless it's inside ``View/keepsStateWhileHidden(_:)``.
- A row of a `List`, `Table` or lazy stack keeps its state when it scrolls out of view, and a collapsed `DisclosureGroup` keeps its content's.

To see how TUI does this, and what a write sets off, read <doc:RenderCycle#How-State-Survives-Re-Rendering>.
