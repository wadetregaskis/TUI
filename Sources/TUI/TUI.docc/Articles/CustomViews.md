# Custom Views

Build your own views by composing existing ones or creating custom view modifiers.

## Overview

TUI offers four ways to create custom views:

| Approach | When to Use | Complexity |
|----------|-------------|------------|
| **Composite View** (``View`` with `body`) | Combining existing views into reusable components | Low |
| **View Modifier** (``ViewModifier``) | A reusable composition around any view, exactly as in SwiftUI | Low |
| **Buffer Modifier** (``BufferModifier``) | Transforming any view's rendered buffer, cell by cell | Medium |
| **Drawn View** (``View`` and ``Renderable``) | Drawing cells yourself, with no views to compose | High |

Most custom views should be **composite views**, and most custom modifiers
**view modifiers**. A buffer modifier is TUI's own: reach for it only when the
transformation has to work on the rendered cells rather than on views. A drawn
view is TUI's own too, a view that returns a ``FrameBuffer`` in place of a `body`:
<doc:AnimatingYourOwnView> shows one, with what it takes to animate without
rendering every frame.

> Note: Views are built on the main actor. A `body` already is, so most code never
> notices, but SwiftUI lets you build a view anywhere and TUI doesn't: a function,
> a static member or a model's method that makes a view, a `@ViewBuilder` helper
> among them, needs `@MainActor` when it isn't inside a view. Without it the
> compiler says `call to main actor-isolated initializer`.

## Composite Views

A composite view implements the `body` property to compose existing views. This is the same pattern as SwiftUI:

```swift
struct StatusHeader: View {
    let title: String
    let version: String

    var body: some View {
        VStack {
            HStack {
                Text(title)
                    .bold()
                    .foregroundStyle(.palette.accent)
                Spacer()
                Text("v\(version)")
                    .foregroundStyle(.palette.foregroundTertiary)
            }
            Divider()
        }
    }
}
```

The `body` property is annotated with `@ViewBuilder` at the protocol level, so you can use all result builder features: conditionals, optionals, loops:

```swift
struct UserCard: View {
    let name: String
    let role: String?

    var body: some View {
        Panel(name) {
            Text(name).bold()
            if let role {
                Text(role)
                    .foregroundStyle(.palette.foregroundSecondary)
                    .italic()
            }
        }
    }
}
```

### Accepting Child Content

To create container-style views that accept child content, use a `@ViewBuilder` closure parameter:

```swift
struct Section<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .bold()
                .underline()
            content
        }
    }
}

// Usage
Section(title: "Settings") {
    Text("Option A")
    Text("Option B")
}
```

### Building Custom Containers

For richer containers, compose existing container views like ``Panel``, ``Card``, or ``Dialog``:

```swift
struct SettingsGroup<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        Panel(title, borderStyle: .rounded, titleColor: .palette.accent) {
            content
        }
    }
}

// Usage
SettingsGroup("Network") {
    Text("Proxy: none")
    Text("DNS: auto")
}
```

## View Modifiers

A ``ViewModifier`` is SwiftUI's: a `body(content:)` that composes views around
the view it is applied to. It may hold `@State` and read `@Environment`, and its
state belongs to the place it is applied.

```swift
struct Callout: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(1)
            .border(.yellow)
    }
}

extension View {
    func callout() -> some View {
        modifier(Callout())
    }
}

Text("Important!").callout()
```

A view modifier that also conforms to ``Animatable`` animates its
`animatableData`, as an animatable view does.

## Buffer Modifiers

A ``BufferModifier`` transforms an already-rendered ``FrameBuffer``. Use this when your transformation operates on the output of any view:

```swift
struct QuoteModifier: BufferModifier {
    func modify(buffer: FrameBuffer, context: RenderContext) -> FrameBuffer {
        // Transform each line in the buffer: prefix a gutter marker.
        // replacingLines(_:) keeps the buffer's overlays and hit-test
        // regions, shifted by however far the content moved.
        let quoted = buffer.lines.map { "▌ " + $0 }
        return buffer.replacingLines(quoted, overlayShiftX: 2)
    }
}
```

(For colour and background changes, prefer composing the built-in modifiers — `.background(_:)`, `.foregroundStyle(_:)` — over rewriting escape codes by hand.)

Apply it using `.modifier(_:)`:

```swift
Text("Important!")
    .modifier(QuoteModifier())
```

### Convenience Extensions

For a cleaner API, add a `View` extension:

```swift
extension View {
    func quoted() -> some View {
        modifier(QuoteModifier())
    }
}

// Usage
Text("Important!").quoted()
```

### When to Use BufferModifier

Use ``BufferModifier`` when your transformation is a pure buffer-to-buffer operation: adding visual effects, changing backgrounds, or adjusting layout after rendering. The ``RenderContext`` gives you access to:

| Property | Description |
|----------|-------------|
| `availableWidth` | Maximum width in columns for this view |
| `availableHeight` | Maximum height in rows for this view |
| `environment` | Current ``EnvironmentValues`` (palette, focus manager, etc.) |

## Type Erasure with AnyView

When you need to store views of different types in a single variable or return different view types conditionally, use ``AnyView``:

```swift
@MainActor
func makeView(isCompact: Bool) -> AnyView {
    if isCompact {
        return AnyView(Text("Compact"))
    } else {
        return AnyView(
            VStack {
                Text("Full")
                Text("Layout")
            }
        )
    }
}
```

Or use the convenience method, in a `body` or anywhere else on the main actor:

```swift
let view = Text("Hello").asAnyView()
```

`AnyView` captures the concrete view type in a closure, erasing it at the type level while preserving the rendering behavior.

> Tip: Prefer concrete types and `some View` return types over `AnyView`. Type erasure should be a last resort when the type system can't express what you need.

## Building Views Outside body

A view is a value, so any code can build one, as in SwiftUI: a free function like `makeView` above, a helper on an enum, a method of a model, or an actor. `body` and everything that draws run on the main actor.

```swift
func row(_ title: String, count: Int) -> some View {
    HStack {
        Text(title)
        Spacer()
        Text(verbatim: "\(count)")
    }
    .padding(.horizontal, 1)
}
```

A view of your own is on the main actor, because it declares that it conforms to ``View``. Its memberwise initializer can still be called anywhere if every stored property is `Sendable`. If one isn't, as with a generic `Content`, or if you write your own `init`, calling it from a nonisolated function is an error. Either mark the function `@MainActor`, or state the conformance in an extension, which leaves the struct itself nonisolated, with `body` still on the main actor:

```swift
struct Titled<Content: View> {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
}

extension Titled: View {
    var body: some View {
        VStack {
            Text(title).bold()
            content
        }
    }
}
```

A ``Button``'s action is `@MainActor`, as in SwiftUI, so a button built in a free function can still call your main-actor model. The other handlers, such as `onChange(of:)` and `onAppear(perform:)`, take a plain closure, also as in SwiftUI. Written in `body`, such a closure is on the main actor. Written in a free function it isn't, so mark that function `@MainActor` if the closure needs the main actor.

A view holding a closure or another view stays in the isolation that built it, so an actor can't hand one to the main actor. ``Text``, ``Image``, ``Spacer``, ``EmptyView`` and ``EmptyModifier`` are `Sendable`, as they are in SwiftUI, so `static let title = Text("Title")` works, and so does returning a `Text` from an actor.

If your app runs everything on the main actor, you can say so once, in your target's settings in `Package.swift`. Every declaration in the target is then `@MainActor` unless it says otherwise:

```swift
.executableTarget(
    name: "MyApp",
    dependencies: ["TUI"],
    swiftSettings: [.defaultIsolation(MainActor.self)]
)
```

## Running Async Work from a Handler

A handler runs on the main actor, straight away, before the next key press is read, and it can't be `async`. To do slow work, start a `Task` from it. The task runs on the main actor between suspensions, and the app keeps drawing and reading keys while it waits:

```swift
struct SaveButton: View {
    let model: DocumentModel
    @State private var isSaving = false

    var body: some View {
        Button("Save") {
            isSaving = true
            Task {
                await model.save()
                isSaving = false
            }
        }
        .disabled(isSaving)
    }
}
```

Setting `isSaving` before the task starts is what stops a second press from starting a second save. Each `Task` you start is your own: it keeps running if the button goes away, which is usually what you want from a save.

For work tied to a view's life, use ``View/task(priority:_:)`` instead, which starts when the view appears and is cancelled when it goes away, or ``View/task(id:priority:_:)``, which also restarts when a value changes.

## Topics

### Protocols

- ``View``
- ``ViewModifier``
- ``BufferModifier``
- ``Renderable``

### Supporting Types

- ``ViewBuilder``
- ``ModifiedView``
- ``AnyView``
- ``RenderContext``
- ``FrameBuffer``
