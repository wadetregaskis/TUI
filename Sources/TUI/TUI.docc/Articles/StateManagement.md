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

## How Long State Lasts

A view's `body` runs many times, but its `@State` isn't reset each time. The value lasts for as long as the view stays in the tree, wherever the tree puts it:

- The two sides of an `if`/`else` or the cases of a `switch` are different views, each with state of its own. Switching to the other side and back starts the first one afresh.
- A view that leaves the tree loses its state, unless it's inside ``View/keepsStateWhileHidden(_:)``.
- A row of a `List`, `Table` or lazy stack keeps its state when it scrolls out of view, and a collapsed `DisclosureGroup` keeps its content's.

To see how TUI does this, and what a write sets off, read <doc:RenderCycle#How-State-Survives-Re-Rendering>.
