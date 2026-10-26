//  🖥️ TUI — A Terminal UI framework for Swift
//  SceneStorage.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - SceneStorage

/// A property wrapper for state restored per scene. Matches SwiftUI's
/// `@SceneStorage`.
///
/// ```swift
/// struct BrowserView: View {
///     @SceneStorage("selectedTab") private var selectedTab = "inbox"
///
///     var body: some View {
///         TabView(selection: $selectedTab) { … }
///     }
/// }
/// ```
///
/// ## How this differs from `@AppStorage`
///
/// SwiftUI draws the line by *scope*: `@AppStorage` is one value for the whole
/// app, `@SceneStorage` is one per window, so two windows of the same document
/// can be scrolled to different places. So it is here: each window the app
/// opens (`openWindow`) keeps its own, under a namespace of its own.
///
/// - The window opened at launch keeps its values under `scene.`, so
///   `@SceneStorage("tab")` and `@AppStorage("tab")` are different values
///   rather than the same one under two names.
/// - A `Window` scene's window keeps them under `scene.` and its identifier —
///   `scene.inspector.tab` — the same from launch to launch.
/// - Each other window of a group keeps them under `scene.`, its group's
///   identifier (or its place among the app's window scenes, for one with
///   none) and, past the first, the how-manyth of its group opened this
///   session it is — `scene.viewer.tab`, `scene.viewer#2.tab`.
///
/// Which one to reach for is then a statement of intent — "this is where the
/// user was" (a tab, a scroll position, a selection) versus "this is what the
/// user chose" (a theme, a font size).
///
/// > Note: SwiftUI does not guarantee scene storage survives a relaunch — it is
///   for *state restoration*, and the system may discard it. TUI persists it
///   the same way `@AppStorage` persists, so it does survive. Relying on it as
///   durable storage is still a bad idea for the reason SwiftUI names: a value
///   nobody chose deliberately should not outlive the reason it was written.
@propertyWrapper
public struct SceneStorage<Value> {
    /// The key the property was declared with, within its scene's namespace.
    private let key: String

    /// The namespace of the window the property's view is drawn in
    /// (``EnvironmentValues/sceneStorageNamespace``), found where the view is
    /// drawn, before its body runs, as an `@Environment` is: empty for the
    /// window opened at launch. A box, so the copies of the property a body's
    /// closures captured write where their view's window keeps its values;
    /// behind a lock, because the property is `Sendable` where its value is.
    private let sceneNamespace = Lock(initialState: "")

    /// The value used when nothing has been stored.
    private let defaultValue: Value

    /// Where it is stored.
    private let storage: StorageBackend

    /// The namespace that separates scene state from app preferences.
    private static var prefix: String { "scene." }

    /// How the value is read from and written to the store: as itself, or as
    /// its raw value (``StorageCodec``).
    private let codec: any StorageCodec<Value>

    /// Scene storage for `key`, within the scene's namespace, falling back to
    /// `defaultValue`, in `storage`, kept as `codec` says.
    private init(key: String, defaultValue: Value, storage: StorageBackend, codec: any StorageCodec<Value>) {
        self.key = key
        self.defaultValue = defaultValue
        self.storage = storage
        self.codec = codec
    }

    /// The key written: the declared key, in the scene's namespace.
    private var scopedKey: String {
        Self.prefix + sceneNamespace.withLock { $0 } + key
    }

    /// The current value.
    public var wrappedValue: Value {
        get {
            codec.read(storage, scopedKey) ?? defaultValue
        }
        nonmutating set {
            // Observed per key, as an `@Observable` property is: the store's
            // `setValue` announces the change through the key's `StoredKey`,
            // which invalidates every view that read the key — in its body, or
            // through a control's `Binding` under a kept result — and nothing
            // else, and asks for a frame. See `StoredKey` for why this used to
            // clear the whole render cache on every write.
            codec.write(storage, scopedKey, newValue)
        }
    }

    /// A binding to the stored value.
    public var projectedValue: Binding<Value> {
        Binding(
            get: { self.wrappedValue },
            set: { self.wrappedValue = $0 }
        )
    }
}

// MARK: - Codable Values

extension SceneStorage where Value: Codable {
    /// Creates scene storage with the default backend.
    ///
    /// - Parameters:
    ///   - wrappedValue: The value to use before anything is stored.
    ///   - key: The key to store under, within the scene's namespace.
    public init(wrappedValue: Value, _ key: String) {
        self.init(key: key, defaultValue: wrappedValue, storage: StorageDefaults.backend, codec: CodableStorageCodec<Value>())
    }

    /// Creates scene storage with a custom backend.
    ///
    /// - Parameters:
    ///   - wrappedValue: The value to use before anything is stored.
    ///   - key: The key to store under, within the scene's namespace.
    ///   - storage: Where to store it.
    public init(wrappedValue: Value, _ key: String, store storage: StorageBackend) {
        self.init(key: key, defaultValue: wrappedValue, storage: storage, codec: CodableStorageCodec<Value>())
    }

    /// Creates scene storage for an optional value, `nil` until something is
    /// stored — mirrors SwiftUI's `init(_:)`.
    ///
    /// - Parameter key: The key to store under, within the scene's namespace.
    public init<Wrapped>(_ key: String) where Value == Wrapped? {
        self.init(key: key, defaultValue: nil, storage: StorageDefaults.backend, codec: CodableStorageCodec<Value>())
    }
}

// MARK: - Raw-Representable Values

extension SceneStorage where Value: RawRepresentable, Value.RawValue: Codable {
    /// Creates scene storage for a raw-representable value, stored as its raw
    /// value — mirrors SwiftUI's `init(wrappedValue:_:)` for a `String` or
    /// `Int` raw value, and takes any `Codable` one.
    ///
    /// Disfavoured, so a type that is `Codable` too keeps the `Codable` form.
    ///
    /// - Parameters:
    ///   - wrappedValue: The value to use before anything is stored.
    ///   - key: The key to store under, within the scene's namespace.
    @_disfavoredOverload
    public init(wrappedValue: Value, _ key: String) {
        self.init(key: key, defaultValue: wrappedValue, storage: StorageDefaults.backend, codec: RawValueStorageCodec<Value>())
    }

    /// Creates scene storage for a raw-representable value with a custom
    /// backend, stored as its raw value.
    ///
    /// - Parameters:
    ///   - wrappedValue: The value to use before anything is stored.
    ///   - key: The key to store under, within the scene's namespace.
    ///   - storage: Where to store it.
    @_disfavoredOverload
    public init(wrappedValue: Value, _ key: String, store storage: StorageBackend) {
        self.init(key: key, defaultValue: wrappedValue, storage: storage, codec: RawValueStorageCodec<Value>())
    }
}

extension SceneStorage {
    /// Creates scene storage for an optional raw-representable value, `nil`
    /// until something is stored, stored as its raw value — mirrors SwiftUI's
    /// `init(_:)` for a raw-representable.
    ///
    /// - Parameter key: The key to store under, within the scene's namespace.
    @_disfavoredOverload
    public init<R>(_ key: String) where Value == R?, R: RawRepresentable, R.RawValue: Codable {
        self.init(key: key, defaultValue: nil, storage: StorageDefaults.backend, codec: OptionalRawValueStorageCodec<R>())
    }
}

// MARK: - Sendability

/// Sendable exactly when the value it stores is — see the note on
/// ``AppStorage``, which this mirrors down to the stored properties.
///
/// SwiftUI spells its own as `@unchecked Sendable where Value: Sendable`; this
/// one needs no `@unchecked`, because the three things it stores are a
/// `String`, a `Value` and a ``StorageBackend``, and the constraint covers the
/// only one of those that isn't already `Sendable`.
extension SceneStorage: Sendable where Value: Sendable {}

extension SceneStorage: FrameworkDynamicProperty {}

// MARK: - Finding the Scene

extension SceneStorage: EnvironmentResolvable {
    /// Hands the property the namespace of the window its view is drawn in,
    /// before the view's body runs.
    public func resolveEnvironment(_ environment: EnvironmentValues) {
        let namespace = environment.sceneStorageNamespace
        sceneNamespace.withLock { $0 = namespace }
    }
}

private struct SceneStorageNamespaceKey: EnvironmentKey {
    static let defaultValue = ""
}

extension EnvironmentValues {
    /// Where the `@SceneStorage` of the window being drawn keeps its values,
    /// after `scene.`: empty for the window opened at launch, and for any
    /// other window its scene's and, past its group's first, its own, each
    /// ending in a dot. Set by the app's scene presenter.
    package var sceneStorageNamespace: String {
        get { self[SceneStorageNamespaceKey.self] }
        set { self[SceneStorageNamespaceKey.self] = newValue }
    }
}
