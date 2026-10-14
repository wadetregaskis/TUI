//  🖥️ TUIkit — Terminal UI Kit for Swift
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
/// ## How this differs from `@AppStorage` — and why it mostly doesn't
///
/// SwiftUI draws the line by *scope*: `@AppStorage` is one value for the whole
/// app, `@SceneStorage` is one per window, so two windows of the same document
/// can be scrolled to different places. That distinction is real when an app
/// has several scenes and meaningless when it has one — and a terminal app has
/// exactly one, filling the terminal. SwiftUI behaves the same way in that
/// case, which is the point: the same source keeps working.
///
/// So the two differ here in exactly one respect, and it is the one that
/// survives having a single scene: **the namespace**. Scene storage is written
/// under a `scene.` prefix, so `@SceneStorage("tab")` and `@AppStorage("tab")`
/// are different values rather than the same one under two names. Which one to
/// reach for is then a statement of intent — "this is where the user was" (a
/// tab, a scroll position, a selection) versus "this is what the user chose" (a
/// theme, a font size) — and that intent is worth keeping legible even when the
/// mechanism underneath is shared.
///
/// > Note: SwiftUI does not guarantee scene storage survives a relaunch — it is
///   for *state restoration*, and the system may discard it. TUIkit persists it
///   the same way `@AppStorage` persists, so it does survive. Relying on it as
///   durable storage is still a bad idea for the reason SwiftUI names: a value
///   nobody chose deliberately should not outlive the reason it was written.
@propertyWrapper
public struct SceneStorage<Value> {
    /// The scene-scoped key actually written.
    private let key: String

    /// The value used when nothing has been stored.
    private let defaultValue: Value

    /// Where it is stored.
    private let storage: StorageBackend

    /// The namespace that separates scene state from app preferences.
    private static var prefix: String { "scene." }

    /// How the value is read from and written to the store: as itself, or as
    /// its raw value (``StorageCodec``).
    private let codec: StorageCodec<Value>

    /// Scene storage for `key`, within the scene's namespace, falling back to
    /// `defaultValue`, in `storage`, kept as `codec` says.
    private init(key: String, defaultValue: Value, storage: StorageBackend, codec: StorageCodec<Value>) {
        self.key = Self.prefix + key
        self.defaultValue = defaultValue
        self.storage = storage
        self.codec = codec
    }

    /// The current value.
    public var wrappedValue: Value {
        get {
            codec.read(storage, key) ?? defaultValue
        }
        nonmutating set {
            // Observed per key, as an `@Observable` property is: the store's
            // `setValue` announces the change through the key's `StoredKey`,
            // which invalidates every view that read the key — in its body, or
            // through a control's `Binding` under a kept result — and nothing
            // else, and asks for a frame. See `StoredKey` for why this used to
            // clear the whole render cache on every write.
            codec.write(storage, key, newValue)
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
        self.init(key: key, defaultValue: wrappedValue, storage: StorageDefaults.backend, codec: CodableStorageCodec())
    }

    /// Creates scene storage with a custom backend.
    ///
    /// - Parameters:
    ///   - wrappedValue: The value to use before anything is stored.
    ///   - key: The key to store under, within the scene's namespace.
    ///   - storage: Where to store it.
    public init(wrappedValue: Value, _ key: String, store storage: StorageBackend) {
        self.init(key: key, defaultValue: wrappedValue, storage: storage, codec: CodableStorageCodec())
    }

    /// Creates scene storage for an optional value, `nil` until something is
    /// stored — mirrors SwiftUI's `init(_:)`.
    ///
    /// - Parameter key: The key to store under, within the scene's namespace.
    public init<Wrapped>(_ key: String) where Value == Wrapped? {
        self.init(key: key, defaultValue: nil, storage: StorageDefaults.backend, codec: CodableStorageCodec())
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
        self.init(key: key, defaultValue: wrappedValue, storage: StorageDefaults.backend, codec: RawValueStorageCodec())
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
        self.init(key: key, defaultValue: wrappedValue, storage: storage, codec: RawValueStorageCodec())
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
