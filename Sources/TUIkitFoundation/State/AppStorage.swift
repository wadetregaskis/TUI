//  🖥️ TUIkit — Terminal UI Kit for Swift
//  AppStorage.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation

// MARK: - JSON File Storage

/// A storage backend that persists data to a JSON file.
///
/// This is the default storage backend for TUIkit apps. Data is stored in the
/// app-specific configuration directory (see `appConfigDirectory()`):
/// `~/Library/Application Support/[appName]/settings.json` on macOS, or
/// `$XDG_CONFIG_HOME/[appName]/settings.json` (else `~/.config/...`) elsewhere.
public final class JSONFileStorage: StorageBackend, @unchecked Sendable {
    /// The file URL for the storage file.
    private let fileURL: URL

    /// Every key this store has read, loaded or written, guarded by `lock`:
    /// its persisted bytes, the value they last decoded to, and its
    /// ``StoredKey``. A key read and never stored keeps an entry with no bytes,
    /// so the readers waiting on its `StoredKey` hear of the first write.
    private var entries: [String: StoredEntry] = [:]

    /// The keys THIS instance has written or removed, guarded by `lock`.
    ///
    /// A flush merges these — and only these — over what is currently on
    /// disk. Snapshotting the whole cache instead rewrote the entire file
    /// from a copy loaded once at startup, so two instances of one app (two
    /// terminal tabs) silently clobbered each other's saved settings: the
    /// second to write anything erased everything the first had saved since
    /// launch. Merging per key narrows a lost update to a key both actually
    /// contested.
    private var dirtyKeys: Set<String> = []

    /// Lock for thread safety. Guards `entries` and `savePending` — and nothing
    /// slow: disk writes snapshot under the lock and write outside it.
    private let lock = NSLock()

    /// Serialises every disk write. A dedicated serial queue rather than
    /// `Task.detached` for three reasons: writes land in submission order (two
    /// detached saves could race and let an older snapshot win the file);
    /// `synchronize()` can flush *behind* any queued save with a plain
    /// `queue.sync`; and a slow disk never occupies a width-limited
    /// cooperative-pool thread.
    ///
    /// wasip1 has no threads, so it has no queue either, and the two properties
    /// the queue was buying — ordering and coalescing — are already the
    /// property of a single thread that does the write where it stands. The
    /// arms below say so at each of the two hops rather than pretending to a
    /// concurrency this platform does not have.
    #if !canImport(WASILibc)
        private let saveQueue = DispatchQueue(label: "TUIkit.JSONFileStorage.save", qos: .utility)
    #endif

    /// Whether a save is already queued. Writes arrive in bursts (a slider
    /// bound to storage emits one per tick); one queued flush snapshots
    /// whatever the cache holds when it runs, so the burst costs one disk
    /// write, not one per tick.
    private var savePending = false

    /// Creates a JSON file storage with default location.
    public init() {
        let configDir = appConfigDirectory()

        // Create directory if needed. A failure here is not fatal — the write
        // may still succeed if the directory already exists — but it is the
        // usual first sign that the config path is unwritable, so it is
        // reported rather than dropped.
        do {
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        } catch {
            StorageDiagnostics.report(
                StorageFailure(
                    operation: .createDirectory, path: configDir.path, underlying: error))
        }

        self.fileURL = configDir.appendingPathComponent("settings.json")
        loadFromDisk()
    }

    /// Creates a JSON file storage with a custom file URL.
    public init(fileURL: URL) {
        self.fileURL = fileURL
        loadFromDisk()
    }
}

// MARK: - Public API

extension JSONFileStorage {
    /// The value stored for `key` as `T`, or `nil` when absent or
    /// undecodable, with the key's ``StoredKey``.
    ///
    /// Served from memory, never from disk, because this is read on the
    /// render path: the value the bytes last decoded to when it is a `T`, else
    /// decoded from the bytes the file was loaded into at init (see
    /// `StoredEntry`). A decode failure is silent for the reason the whole
    /// family shares: falling back to the caller's default is ``AppStorage``'s
    /// defined behaviour, not an error — and reporting it would fire every
    /// frame for as long as the value stayed in the file. See
    /// ``StorageDiagnostics``.
    public func entry<T: Codable>(forKey key: String, as type: T.Type) -> (value: T?, key: StoredKey) {
        lock.lock()
        defer { lock.unlock() }
        let entry = entryLocked(key)
        return (entry.value(as: T.self), entry.key)
    }

    /// Stores `value` for `key` and schedules a write.
    ///
    /// The value in memory is updated synchronously — a read straight after a
    /// write sees the new value — while the file is written on a serial queue,
    /// so a per-keystroke setting does not put file I/O in the frame. Encode
    /// failures report through ``StorageDiagnostics``; see
    /// ``synchronize()`` for the flush that makes a pending write durable.
    public func store<T: Codable>(_ value: T, forKey key: String) -> StoredKey {
        let data: Data
        do {
            data = try JSONEncoder().encode(value)
        } catch {
            // Reported before the lock is taken at all, deliberately, rather
            // than from a `catch` inside the critical section: ``report`` runs
            // the app's handler synchronously on this thread, and `lock` is a
            // plain `NSLock`. A handler that touches this backend — even just
            // `value(forKey:)`, the coalescing ``StorageDiagnostics`` invites —
            // re-entered it and hung the app for good. `flushToDisk` reports
            // after its own unlock for the same reason.
            StorageDiagnostics.report(
                StorageFailure(operation: .encode, key: key, path: fileURL.path, underlying: error))
            lock.lock()
            defer { lock.unlock() }
            return entryLocked(key).key
        }

        lock.lock()
        defer { lock.unlock() }

        let entry = entryLocked(key)
        entry.set(value, encoded: data)
        dirtyKeys.insert(key)
        saveToDiskAsync()
        return entry.key
    }

    /// Removes any value stored for `key`, scheduling the write as
    /// ``store(_:forKey:)`` does.
    public func remove(forKey key: String) -> StoredKey? {
        lock.lock()
        defer { lock.unlock() }

        let entry = entries[key]
        entry?.clear()
        dirtyKeys.insert(key)
        saveToDiskAsync()
        return entry?.key
    }

    /// Blocks until everything written so far is on disk.
    ///
    /// Call before exiting: writes are otherwise queued, and a terminal app
    /// can be killed by a signal between frames.
    public func synchronize() {
        // A plain sync hop onto the serial save queue: any already-queued
        // asynchronous save runs first, then this flush writes whatever the
        // cache holds now — so "synchronize then exit" cannot lose a value.
        #if canImport(WASILibc)
            flushToDisk()
        #else
            saveQueue.sync {
                self.flushToDisk()
            }
        #endif
    }
}

// MARK: - Private Helpers

extension JSONFileStorage {
    /// The entry for `key`, made empty if there is none (caller holds `lock`).
    fileprivate func entryLocked(_ key: String) -> StoredEntry {
        if let entry = entries[key] { return entry }
        let entry = StoredEntry()
        entries[key] = entry
        return entry
    }

    fileprivate func loadFromDisk() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            if let decoded = try JSONSerialization.jsonObject(with: data) as? [String: String] {
                // Convert base64 strings back to Data
                for (key, base64String) in decoded {
                    if let valueData = Data(base64Encoded: base64String) {
                        entries[key] = StoredEntry(data: valueData)
                    }
                }
            }
        } catch {
            // Starting fresh is the right recovery, but the app has just lost
            // every stored setting and should be able to say so.
            StorageDiagnostics.report(
                StorageFailure(operation: .load, path: fileURL.path, underlying: error))
        }
    }

    /// Queues one flush (caller holds `lock`). Bursts coalesce: if a flush is
    /// already queued it will snapshot this write too, so a slider dragging a
    /// bound value costs one disk write per drain, not one per tick.
    fileprivate func saveToDiskAsync() {
        guard !savePending else { return }
        savePending = true
        #if canImport(WASILibc)
            // Inline, and therefore synchronous: the burst-coalescing above still
            // holds (`savePending` is cleared by the flush), and a write that
            // cannot be deferred to another thread is better done now than not
            // at all.
            flushToDisk()
        #else
            saveQueue.async { [weak self] in
                self?.flushToDisk()
            }
        #endif
    }

    /// Runs only on `saveQueue`. Snapshots this instance's changes under the
    /// lock, then serialises and writes OUTSIDE it — the old detached save
    /// iterated the cache with no lock at all, racing `setValue`'s mutation on
    /// the main thread (a CoW dictionary read overlapping a mutation of the
    /// same reference).
    fileprivate func flushToDisk() {
        lock.lock()
        savePending = false
        let changed = dirtyKeys.map { ($0, entries[$0]?.data) }
        lock.unlock()

        // Start from what is on disk NOW — another instance may have written
        // since this one loaded — and overlay only this instance's own
        // changes. See `dirtyKeys`. A fresh read each flush rather than a
        // kept file handle: flushes are rare (bursts coalesce), and the read
        // is what makes a sibling's keys survive.
        var serializable: [String: String] = [:]
        if let data = try? Data(contentsOf: fileURL),
            let onDisk = try? JSONSerialization.jsonObject(with: data) as? [String: String]
        {
            serializable = onDisk
        }
        for (key, data) in changed {
            serializable[key] = data?.base64EncodedString()
        }

        do {
            let data = try JSONSerialization.data(withJSONObject: serializable, options: .prettyPrinted)
            // Atomically where the platform can: a half-written settings file
            // is worse than a stale one. WASI's Foundation refuses the option
            // outright — atomic writing goes through a temporary file and a
            // rename, and wasip1 has no temporary directory to make one in — so
            // there the write is direct, and a host that cares about the
            // difference has to provide durability of its own.
            #if canImport(WASILibc)
                try data.write(to: fileURL)
            #else
                try data.write(to: fileURL, options: .atomic)
            #endif
        } catch {
            // The write that just failed is the whole point of the API: without
            // this report the app shows a saved setting that will not survive
            // the next launch.
            StorageDiagnostics.report(
                StorageFailure(operation: .save, path: fileURL.path, underlying: error))
        }
    }
}

// MARK: - Storage Defaults

/// Provides the default storage backend for ``AppStorage``.
///
/// Override the backend before creating any `@AppStorage` properties
/// if you want to use a custom storage backend. To use another store for
/// part of an app only, set it with `defaultAppStorage(_:)` on a view or a
/// scene instead.
///
/// ```swift
/// StorageDefaults.backend = MyCustomBackend()
/// ```
public enum StorageDefaults {
    /// The default storage backend used by ``AppStorage``.
    ///
    /// Matches SwiftUI's `@AppStorage`, which is backed by `UserDefaults`:
    /// - **Apple platforms**: ``UserDefaultsStorage`` over `UserDefaults.standard`,
    ///   so values land in the system preferences domain —
    ///   `~/Library/Preferences/<bundle-identifier>.plist` when the app is bundled
    ///   (the identifier comes from its `Info.plist`), else
    ///   `~/Library/Preferences/<executable-name>.plist` for a plain CLI binary.
    /// - **Linux / other**: ``JSONFileStorage``, since Foundation's `UserDefaults`
    ///   does not reliably persist there — written under `appConfigDirectory()`
    ///   (`$XDG_CONFIG_HOME/<app>/settings.json`, else `~/.config/<app>/…`).
    ///
    /// Setting `TUIKIT_CONFIG_DIR` in the environment overrides both: storage
    /// becomes file-backed under that directory on every platform. That is the
    /// isolation hook for test harnesses — on Apple platforms `UserDefaults`
    /// ignores a `$HOME` override, so without it a "sandboxed" run reads and
    /// writes the developer's real preferences domain.
    ///
    /// Override before creating any `@AppStorage` properties to use a custom backend.
    nonisolated(unsafe) public static var backend: StorageBackend = {
        if let override = ProcessInfo.processInfo.environment["TUIKIT_CONFIG_DIR"],
            !override.isEmpty
        {
            // JSONFileStorage roots itself at appConfigDirectory(), which
            // honours the same override.
            return JSONFileStorage()
        }
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
            return UserDefaultsStorage()
        #else
            return JSONFileStorage()
        #endif
    }()
}

// MARK: - AppStorage Property Wrapper

/// A property wrapper that reads and writes to persistent storage.
///
/// Use `@AppStorage` to persist simple values across app launches.
/// Values are `Codable`, or `RawRepresentable` with a `Codable` raw value,
/// which is what is stored.
///
/// # Example
///
/// ```swift
/// struct SettingsView: View {
///     @AppStorage("username") var username = "Guest"
///     @AppStorage("darkMode") var darkMode = false
///     @AppStorage("fontSize") var fontSize = 14
///
///     var body: some View {
///         VStack {
///             Text("User: \(username)")
///             Text("Dark Mode: \(darkMode ? "On" : "Off")")
///         }
///     }
/// }
/// ```
///
/// # Supported Types
///
/// Any type that conforms to `Codable`:
/// - String, Int, Double, Bool
/// - Date, Data, URL
/// - Arrays and Dictionaries of Codable types
/// - Custom Codable structs and enums
///
/// And any `RawRepresentable` type whose raw value is `Codable` — an
/// `enum Mode: String { … }`, SwiftUI's commonest `@AppStorage` after a
/// `Bool` — stored as its raw value; a stored raw value that is no case reads
/// as nothing stored. SwiftUI takes `String` and `Int` raw values; any
/// `Codable` one is taken here. A type that is both, an `enum Mode: String,
/// Codable`, is stored by its `Codable` form, which for such an enum is its raw
/// value too.
///
/// # Where it is stored
///
/// A property that names a store (`store:`) uses it. One that names none uses
/// the store `defaultAppStorage(_:)` set nearest above its view — found where the view is drawn, before its `body` runs, as an
/// `@Environment` is — and ``StorageDefaults/backend`` where none is set. A
/// closure the body made, a button's action say, writes to the store found
/// for the body that made it.
@propertyWrapper
public struct AppStorage<Value> {
    /// The key used for storage.
    private let key: String

    /// The default value if no stored value exists.
    private let defaultValue: Value

    /// How the value is read from and written to a store: as itself, or as its
    /// raw value.
    private let codec: StorageCodec<Value>

    /// The store the property named, or `nil` for the one its view's
    /// environment names.
    private let namedStore: (any StorageBackend)?

    /// For a property that names no store: the store `defaultAppStorage(_:)`
    /// set where its view was last drawn, or `nil` where none was set.
    ///
    /// A box, so that the copies of the property a body's closures captured
    /// see what is found for the view they came from; behind a lock, because
    /// the property is `Sendable` (where its value is) and may be read off the
    /// main actor while a walk sets this on it. `nil` for a property that
    /// names a store, which never reads it.
    private let environmentStore: Lock<(any StorageBackend)?>?

    /// The property for `key`, falling back to `defaultValue`, in `store`, or
    /// in its view's default store when that is `nil`, kept as `codec` says.
    private init(key: String, defaultValue: Value, store: (any StorageBackend)?, codec: StorageCodec<Value>) {
        self.key = key
        self.defaultValue = defaultValue
        self.codec = codec
        self.namedStore = store
        self.environmentStore = store == nil ? Lock(initialState: nil) : nil
    }

    /// The store read and written: the one named, else the one found for the
    /// view, else the process's default.
    private var storage: any StorageBackend {
        if let namedStore { return namedStore }
        return environmentStore?.withLock { $0 } ?? StorageDefaults.backend
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

extension AppStorage where Value: Codable {
    /// Creates an AppStorage with the default storage backend.
    ///
    /// - Parameters:
    ///   - wrappedValue: The default value.
    ///   - key: The key to use for storage.
    public init(wrappedValue: Value, _ key: String) {
        self.init(key: key, defaultValue: wrappedValue, store: nil)
    }

    /// Creates an AppStorage with a custom storage backend.
    ///
    /// - Parameters:
    ///   - wrappedValue: The default value.
    ///   - key: The key to use for storage.
    ///   - storage: The storage backend to use.
    public init(wrappedValue: Value, _ key: String, store storage: any StorageBackend) {
        self.init(key: key, defaultValue: wrappedValue, store: storage)
    }

    /// Creates an AppStorage for an optional value, `nil` until something is
    /// stored — mirrors SwiftUI's `init(_:store:)`.
    ///
    /// Disfavoured, so that where SwiftUI's `UserDefaults` form exists
    /// alongside it, `@AppStorage("key") var value: Int?` means that one, as
    /// it does in SwiftUI. Both use the environment's store when given none.
    ///
    /// - Parameters:
    ///   - key: The key to use for storage.
    ///   - storage: The storage backend to use, or `nil` for the default.
    @_disfavoredOverload
    public init<Wrapped>(_ key: String, store storage: (any StorageBackend)? = nil) where Value == Wrapped? {
        self.init(key: key, defaultValue: nil, store: storage)
    }

    /// The property for `key`, falling back to `defaultValue`, in `store`, or
    /// in its view's default store when that is `nil`.
    ///
    /// Spelled with labels no public form shares, so the forms TUIkit's other
    /// modules add (a tab view's customization, a table's columns) can reach
    /// it without resolving back to themselves.
    package init(key: String, defaultValue: Value, store: (any StorageBackend)?) {
        self.init(key: key, defaultValue: defaultValue, store: store, codec: CodableStorageCodec<Value>())
    }
}

// MARK: - Raw-Representable Values

extension AppStorage where Value: RawRepresentable, Value.RawValue: Codable {
    /// Creates an AppStorage for a raw-representable value, stored as its raw
    /// value — mirrors SwiftUI's `init(wrappedValue:_:store:)` for a `String`
    /// or `Int` raw value, and takes any `Codable` one.
    ///
    /// Disfavoured, so a type that is `Codable` too keeps the `Codable` form
    /// it had before this one existed.
    ///
    /// - Parameters:
    ///   - wrappedValue: The default value.
    ///   - key: The key to use for storage.
    @_disfavoredOverload
    public init(wrappedValue: Value, _ key: String) {
        self.init(key: key, defaultValue: wrappedValue, store: nil, codec: RawValueStorageCodec<Value>())
    }

    /// Creates an AppStorage for a raw-representable value in a custom storage
    /// backend, stored as its raw value.
    ///
    /// - Parameters:
    ///   - wrappedValue: The default value.
    ///   - key: The key to use for storage.
    ///   - storage: The storage backend to use.
    @_disfavoredOverload
    public init(wrappedValue: Value, _ key: String, store storage: any StorageBackend) {
        self.init(key: key, defaultValue: wrappedValue, store: storage, codec: RawValueStorageCodec<Value>())
    }
}

extension AppStorage {
    /// Creates an AppStorage for an optional raw-representable value, `nil`
    /// until something is stored, stored as its raw value — mirrors SwiftUI's
    /// `init(_:store:)` for a raw-representable.
    ///
    /// - Parameters:
    ///   - key: The key to use for storage.
    ///   - storage: The storage backend to use, or `nil` for the default.
    @_disfavoredOverload
    public init<R>(_ key: String, store storage: (any StorageBackend)? = nil)
    where Value == R?, R: RawRepresentable, R.RawValue: Codable {
        self.init(key: key, defaultValue: nil, store: storage, codec: OptionalRawValueStorageCodec<R>())
    }
}

// MARK: - Codecs

/// How an ``AppStorage`` or a ``SceneStorage`` keeps its value in a store: as
/// itself, for a `Codable` value, or as its raw value, for a raw-representable
/// one — one subclass each, overriding both methods.
///
/// A class rather than a pair of `Sendable` closures, which captured the
/// value type's metatype (Swift 6.2 warns of it, SendableMetatypes), and
/// rather than an `any` of a protocol with a primary associated type: stored
/// here, that crashed every test that made an `AppStorage` (signal 11 under
/// Xcode's Swift 6.2.4, deployment target macOS 14; the cause was not
/// pinned down — no rendering was involved). Immutable, so unchecked-`Sendable`
/// is sound.
class StorageCodec<Value>: @unchecked Sendable {
    /// The value stored for `key`, or `nil` where there is none to read.
    func read(_ store: any StorageBackend, _ key: String) -> Value? { nil }

    /// Stores `value` for `key`.
    func write(_ store: any StorageBackend, _ key: String, _ value: Value) {}
}

/// The value itself.
final class CodableStorageCodec<Value: Codable>: StorageCodec<Value>, @unchecked Sendable {
    override func read(_ store: any StorageBackend, _ key: String) -> Value? { store.value(forKey: key) }
    override func write(_ store: any StorageBackend, _ key: String, _ value: Value) { store.setValue(value, forKey: key) }
}

/// The raw value; one that is no case reads as nothing stored.
final class RawValueStorageCodec<Value: RawRepresentable>: StorageCodec<Value>, @unchecked Sendable
where Value.RawValue: Codable {
    override func read(_ store: any StorageBackend, _ key: String) -> Value? {
        (store.value(forKey: key) as Value.RawValue?).flatMap(Value.init(rawValue:))
    }

    override func write(_ store: any StorageBackend, _ key: String, _ value: Value) {
        store.setValue(value.rawValue, forKey: key)
    }
}

/// An optional raw-representable's raw value; its `nil` as an optional raw
/// value's `nil`.
final class OptionalRawValueStorageCodec<Wrapped: RawRepresentable>: StorageCodec<Wrapped?>, @unchecked Sendable
where Wrapped.RawValue: Codable {
    override func read(_ store: any StorageBackend, _ key: String) -> Wrapped?? {
        guard let raw: Wrapped.RawValue = store.value(forKey: key), let value = Wrapped(rawValue: raw) else { return nil }
        return .some(value)
    }

    override func write(_ store: any StorageBackend, _ key: String, _ value: Wrapped?) {
        store.setValue(value.map(\.rawValue), forKey: key)
    }
}

// MARK: - SwiftUI's UserDefaults Forms

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    extension AppStorage where Value: Codable {
        /// Creates a property that reads and writes `key` in `store` —
        /// mirrors SwiftUI's `init(wrappedValue:_:store:)`.
        ///
        /// Takes any `Codable` value, where SwiftUI's takes the property-list
        /// types and raw-representable ones. A property-list value is stored
        /// as itself, as SwiftUI stores it, and any other as its JSON encoding
        /// (``UserDefaultsStorage``).
        ///
        /// - Parameters:
        ///   - wrappedValue: The default value if a value is not specified
        ///     for the given key.
        ///   - key: The key to read and write the value to in the user
        ///     defaults store.
        ///   - store: The user defaults store to read and write to, or `nil`
        ///     for the store the view's environment names
        ///     (`defaultAppStorage(_:)`).
        public init(wrappedValue: Value, _ key: String, store: UserDefaults?) {
            self.init(key: key, defaultValue: wrappedValue, store: store.map { UserDefaultsStorage($0) })
        }

        /// Creates a property for an optional value, `nil` until something
        /// is stored, in `store` — mirrors SwiftUI's `init(_:store:)`.
        ///
        /// - Parameters:
        ///   - key: The key to read and write the value to in the user
        ///     defaults store.
        ///   - store: The user defaults store to read and write to, or `nil`
        ///     for the store the view's environment names.
        public init<Wrapped>(_ key: String, store: UserDefaults? = nil) where Value == Wrapped? {
            self.init(key: key, defaultValue: nil, store: store.map { UserDefaultsStorage($0) })
        }
    }

    extension AppStorage where Value: RawRepresentable, Value.RawValue: Codable {
        /// Creates a property for a raw-representable value that reads and
        /// writes `key` in `store`, stored as its raw value — mirrors SwiftUI's
        /// `init(wrappedValue:_:store:)` for a `String` or `Int` raw value.
        ///
        /// - Parameters:
        ///   - wrappedValue: The default value if a value is not specified
        ///     for the given key.
        ///   - key: The key to read and write the value to in the user
        ///     defaults store.
        ///   - store: The user defaults store to read and write to, or `nil`
        ///     for the store the view's environment names.
        @_disfavoredOverload
        public init(wrappedValue: Value, _ key: String, store: UserDefaults?) {
            self.init(
                key: key, defaultValue: wrappedValue, store: store.map { UserDefaultsStorage($0) }, codec: RawValueStorageCodec<Value>())
        }
    }

    extension AppStorage {
        /// Creates a property for an optional raw-representable value, `nil`
        /// until something is stored, in `store`, stored as its raw value —
        /// mirrors SwiftUI's `init(_:store:)` for a raw-representable.
        ///
        /// The store is not defaulted, as SwiftUI's is: written without one,
        /// `@AppStorage("key") var mode: Mode?` takes the form whose store is
        /// a `StorageBackend`, which reads the same store, rather than finding
        /// two forms that fit equally.
        ///
        /// - Parameters:
        ///   - key: The key to read and write the value to in the user
        ///     defaults store.
        ///   - store: The user defaults store to read and write to, or `nil`
        ///     for the store the view's environment names.
        @_disfavoredOverload
        public init<R>(_ key: String, store: UserDefaults?) where Value == R?, R: RawRepresentable, R.RawValue: Codable {
            self.init(key: key, defaultValue: nil, store: store.map { UserDefaultsStorage($0) }, codec: OptionalRawValueStorageCodec<R>())
        }
    }
#endif

// MARK: - Finding the Store

extension AppStorage: EnvironmentResolvable {
    /// Hands a property that names no store the one `defaultAppStorage(_:)`
    /// set where its view is, before the view's body runs.
    public func resolveEnvironment(_ environment: EnvironmentValues) {
        guard let environmentStore else { return }
        let store = environment.defaultAppStorage?.store
        environmentStore.withLock { $0 = store }
    }
}

// MARK: - Sendability

/// Sendable exactly when the value it stores is — and checked, not asserted.
///
/// Conditional for the reason SwiftUI's own conformance is conditional
/// (`extension AppStorage: Sendable where Value: Sendable`): the wrapper is a
/// box, so it is only as safe to send as what is in the box. Every other stored
/// property already qualifies — `key` is a `String`, ``StorageBackend``
/// refines `Sendable` and the box the environment's store is kept in is a
/// lock — so `defaultValue` is the only way anything can cross an
/// isolation boundary inside this struct, and `Value: Codable` does not stop
/// that being a mutable class.
///
/// It used to be spelled `@unchecked Sendable` on the struct itself, with no
/// constraint. That is not SwiftUI parity and it is not sound: it laundered a
/// non-`Sendable` `Value` through the wrapper, so `@AppStorage` was a hole in
/// exactly the checking the rest of the package relies on. Nothing here needs
/// `@unchecked` once the constraint is stated, which is the tell that the
/// annotation was standing in for the constraint.
extension AppStorage: Sendable where Value: Sendable {}

extension AppStorage: FrameworkDynamicProperty {}
