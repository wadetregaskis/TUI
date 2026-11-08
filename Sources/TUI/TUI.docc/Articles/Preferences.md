# Preferences

Pass data from child views up to their ancestors.

## Overview

TUI's preference system enables **bottom-up data flow**: the reverse of environment values. While the environment passes data down from parent to child, preferences let child views publish values that ancestors can observe and react to.

The system mirrors SwiftUI's preference API. The public parts are:

- **``PreferenceKey``**: Protocol that defines a named value type with a default and a reduce strategy
- **``PreferenceValues``**: Type-safe storage that holds all preference values for a scope

Behind them, the framework's own `PreferenceStorage` collects values per render pass; you never touch it.

A built-in example is ``NavigationTitleKey``: a child view sets `.navigationTitle("Settings")`, and a pushed ``NavigationStack`` screen reads that preference to draw its title.

## Defining a Preference Key

A preference key declares what type of value it carries and how multiple values from sibling children are combined:

```swift
struct CounterKey: PreferenceKey {
    static let defaultValue: Int = 0

    static func reduce(value: inout Int, nextValue: () -> Int) {
        value += nextValue()
    }
}
```

- **`defaultValue`**: Returned when no child has set this preference
- **`reduce(value:nextValue:)`**: Combines values when multiple children set the same key

The default `reduce` implementation simply takes the last value. Override it when you need additive behavior (summing counts), array collection, or other merge strategies.

## Setting a Preference

Child views publish a preference using the `.preference(key:value:)` modifier:

```swift
struct ItemView: View {
    var body: some View {
        Text("Item")
            .preference(key: CounterKey.self, value: 1)
    }
}
```

Under the hood, this wraps the view in a `PreferenceModifier` that calls `preferences.setValue(_:forKey:)` during rendering. The value is reduced into the current scope using the key's `reduce` function.

## Observing Preferences

Ancestor views react to collected preferences using `.onPreferenceChange(_:perform:)`:

```swift
struct ItemList: View {
    var body: some View {
        VStack {
            ItemView()
            ItemView()
            ItemView()
        }
        .onPreferenceChange(CounterKey.self) { totalCount in
            // totalCount == 3 (three children each set value: 1, additive reduce)
        }
    }
}
```

The key's `Value` must be `Equatable`, as in SwiftUI; a key whose value isn't can still be read with `overlayPreferenceValue` (below).

The modifier pushes a new preference context, renders all children (which set their preferences), pops the context, and fires the callback with the accumulated result.

## The Navigation Title Shortcut

TUI provides ``NavigationTitleKey`` as a built-in preference key with a convenience modifier:

```swift
struct SettingsPage: View {
    var body: some View {
        VStack {
            Text("App settings go here")
        }
        .navigationTitle("Settings")
    }
}
```

`NavigationTitleKey` uses the default `reduce` (last value wins), so in the published preference the deepest child's title takes precedence. The window's own top bar, and the title the terminal window shows, take the **outermost** title instead, the one nearest the root of the window.

## Reading Preferences in an Overlay or Background

To draw something from a preference rather than store it, read it with
``View/overlayPreferenceValue(_:_:)`` or ``View/backgroundPreferenceValue(_:_:)``:
the closure gets the value collected from the view's subtree and returns a view
laid over (or under) it.

```swift
VStack {
    ItemView()
    ItemView()
}
.overlayPreferenceValue(CounterKey.self) { count in
    Text("\(count) items")
}
```

``View/transformPreference(_:_:)`` rewrites a value on its way up, and
``View/anchorPreference(key:value:transform:)`` publishes a view's geometry, as an
``Anchor`` a reader resolves with a ``GeometryProxy``.

## How Preferences Flow per Frame

This section describes the framework's internals; you don't need it to use preferences. Preferences are collected fresh every frame. Here's the lifecycle within a single render pass:

1. **Reset**: `RenderLoop.render()` calls `preferences.beginRenderPass()`, clearing all callbacks and resetting the stack to a single empty context
2. **Set**: As the view tree renders top-down, `PreferenceModifier` views call `setValue(_:forKey:)`, which reduces values into the current stack frame
3. **Scope**: `OnPreferenceChangeModifier` pushes a new context before rendering its subtree, isolating child preferences
4. **Collect**: After the subtree finishes, the modifier pops the context (merging into the parent) and fires the callback with the scoped result
5. **Discard**: At the start of the next frame, everything resets: stale preferences never persist

This per-frame reset ensures preferences always reflect the current view tree. Removed views stop contributing automatically.

## Reduce Strategies

The `reduce` function determines how multiple children's values combine. Common patterns:

| Strategy | Implementation | Use Case |
|----------|---------------|----------|
| Last value wins | `value = nextValue()` (default) | Titles, labels: deepest child wins |
| Additive | `value += nextValue()` | Counting items, summing heights |
| Array collection | `value.append(contentsOf: nextValue())` | Gathering menu items, breadcrumbs |

```swift
// Array collection example
struct BreadcrumbKey: PreferenceKey {
    static let defaultValue: [String] = []

    static func reduce(value: inout [String], nextValue: () -> [String]) {
        value.append(contentsOf: nextValue())
    }
}
```

## Topics

### Protocols

- ``PreferenceKey``
- ``NavigationTitleKey``

### Storage

- ``PreferenceValues``
