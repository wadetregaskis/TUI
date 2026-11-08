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
/// ## Per terminal session
///
/// A terminal window is the nearest thing a terminal app has to the scene a
/// value belongs to, so each value is kept per terminal session too: the
/// window, tab or pane the terminal names in the environment it started the
/// shell with (a tmux pane, `TERM_SESSION_ID`, `KITTY_WINDOW_ID` and the
/// like). A write goes to the session's copy and to a copy shared by every
/// session, the last saved. A read takes the session's copy, else the last
/// saved, else the declared default. So running the app again in the same
/// window puts back where it was in that window, two windows running it at
/// once keep a value each, and a new window — someone who opens one for
/// each task — starts from wherever they last left it.
///
/// Where the terminal names no session, as over a plain ssh connection, there
/// is only the last saved. A store keeps the 32 sessions written most
/// recently, each for 30 days after its last write; one dropped starts from
/// the last saved, as a new one does.
///
/// ## Where it is stored
///
/// As ``AppStorage`` is: in the store a property names (`store:`), else the
/// one `defaultAppStorage(_:)` set above its view, else
/// ``StorageDefaults/backend``. So a test run in `TestApp` keeps its scene
/// storage in memory with its app storage.
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

    /// What the property's view's environment says of where it keeps its
    /// values, found where the view is drawn, before its body runs, as an
    /// `@Environment` is. A box, so the copies of the property a body's
    /// closures captured write where their view's window keeps its values;
    /// behind a lock, because the property is `Sendable` where its value is.
    private let scope = Lock(initialState: SceneStorageScope())

    /// The value used when nothing has been stored.
    private let defaultValue: Value

    /// The store the property named, or `nil` for the one its view's
    /// environment names.
    private let namedStore: (any StorageBackend)?

    /// The namespace that separates scene state from app preferences.
    private static var prefix: String { "scene." }

    /// How the value is read from and written to the store: as itself, or as
    /// its raw value (``StorageCodec``).
    private let codec: any StorageCodec<Value>

    /// Scene storage for `key`, within the scene's namespace, falling back to
    /// `defaultValue`, in `store`, or in its view's default store when that is
    /// `nil`, kept as `codec` says.
    private init(key: String, defaultValue: Value, store: (any StorageBackend)?, codec: any StorageCodec<Value>) {
        self.key = key
        self.defaultValue = defaultValue
        self.namedStore = store
        self.codec = codec
    }

    /// Where the property keeps its values now: the store, the shared key
    /// (the declared key in the scene's namespace) and, if the app runs in a
    /// terminal session, the session and its key.
    private var location: SceneStorageLocation {
        let scope = scope.withLock { $0 }
        let shared = Self.prefix + scope.namespace + key
        return SceneStorageLocation(
            store: namedStore ?? scope.store ?? StorageDefaults.backend,
            shared: shared,
            session: scope.session,
            sessionKey: scope.session.map { SceneStorageSessions.key(shared, session: $0) })
    }

    /// The current value: the session's, else the last saved from any
    /// session, else the default.
    public var wrappedValue: Value {
        get {
            let location = location
            if let sessionKey = location.sessionKey, let value = codec.read(location.store, sessionKey) {
                return value
            }
            return codec.read(location.store, location.shared) ?? defaultValue
        }
        nonmutating set {
            // Observed per key, as an `@Observable` property is: the store's
            // `setValue` announces the change through the key's `StoredKey`,
            // which invalidates every view that read the key — in its body, or
            // through a control's `Binding` under a kept result — and nothing
            // else, and asks for a frame. See `StoredKey` for why this used to
            // clear the whole render cache on every write.
            let location = location
            if let session = location.session, let sessionKey = location.sessionKey {
                codec.write(location.store, sessionKey, newValue)
                SceneStorageSessions.noteWrite(of: sessionKey, session: session, in: location.store, now: Date())
            }
            codec.write(location.store, location.shared, newValue)
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
        self.init(key: key, defaultValue: wrappedValue, store: nil, codec: CodableStorageCodec<Value>())
    }

    /// Creates scene storage with a custom backend.
    ///
    /// - Parameters:
    ///   - wrappedValue: The value to use before anything is stored.
    ///   - key: The key to store under, within the scene's namespace.
    ///   - storage: Where to store it.
    public init(wrappedValue: Value, _ key: String, store storage: StorageBackend) {
        self.init(key: key, defaultValue: wrappedValue, store: storage, codec: CodableStorageCodec<Value>())
    }

    /// Creates scene storage for an optional value, `nil` until something is
    /// stored — mirrors SwiftUI's `init(_:)`.
    ///
    /// - Parameter key: The key to store under, within the scene's namespace.
    public init<Wrapped>(_ key: String) where Value == Wrapped? {
        self.init(key: key, defaultValue: nil, store: nil, codec: CodableStorageCodec<Value>())
    }

    /// Scene storage for `key`, falling back to `defaultValue`, in `store`,
    /// or in its view's default store when that is `nil`.
    ///
    /// Spelled with labels no public form shares, so the forms TUI's other
    /// modules add (a tab view's customization, a table's columns) can reach
    /// it without resolving back to themselves.
    package init(key: String, defaultValue: Value, store: (any StorageBackend)?) {
        self.init(key: key, defaultValue: defaultValue, store: store, codec: CodableStorageCodec<Value>())
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
        self.init(key: key, defaultValue: wrappedValue, store: nil, codec: RawValueStorageCodec<Value>())
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
        self.init(key: key, defaultValue: wrappedValue, store: storage, codec: RawValueStorageCodec<Value>())
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
        self.init(key: key, defaultValue: nil, store: nil, codec: OptionalRawValueStorageCodec<R>())
    }
}

// MARK: - Sendability

/// Sendable exactly when the value it stores is — see the note on
/// ``AppStorage``, which this mirrors down to the stored properties.
///
/// SwiftUI spells its own as `@unchecked Sendable where Value: Sendable`; this
/// one needs no `@unchecked`, because what it stores is a `String`, a `Value`,
/// a ``StorageBackend``, a codec and a lock, and the constraint covers the
/// only one of those that isn't already `Sendable`.
extension SceneStorage: Sendable where Value: Sendable {}

extension SceneStorage: FrameworkDynamicProperty {}

// MARK: - Finding the Scene

extension SceneStorage: EnvironmentResolvable {
    /// Hands the property the namespace of the window its view is drawn in,
    /// the terminal session and the store `defaultAppStorage(_:)` set there,
    /// before the view's body runs.
    public func resolveEnvironment(_ environment: EnvironmentValues) {
        let found = SceneStorageScope(
            namespace: environment.sceneStorageNamespace,
            session: environment.sceneStorageSession,
            store: namedStore == nil ? environment.defaultAppStorage?.store : nil)
        scope.withLock { $0 = found }
    }
}

/// What a ``SceneStorage``'s view's environment says of where it keeps its
/// values.
private struct SceneStorageScope: Sendable {
    /// The namespace of the window the view is drawn in
    /// (``EnvironmentValues/sceneStorageNamespace``): empty for the window
    /// opened at launch.
    var namespace = ""

    /// The terminal session (``EnvironmentValues/sceneStorageSession``), or
    /// `nil` for none.
    var session: String?

    /// The store `defaultAppStorage(_:)` set, for a property that names
    /// none; `nil` for ``StorageDefaults/backend``.
    var store: (any StorageBackend)?
}

/// Where a ``SceneStorage`` reads and writes, worked out from its scope.
private struct SceneStorageLocation {
    /// The store.
    var store: any StorageBackend
    /// The last saved from any session: `scene.`, the window's namespace and
    /// the declared key.
    var shared: String
    /// The terminal session, or `nil` for none.
    var session: String?
    /// The session's own key (``SceneStorageSessions/key(_:session:)``).
    var sessionKey: String?
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
