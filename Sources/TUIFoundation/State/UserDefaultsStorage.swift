//  🖥️ TUI — A Terminal UI framework for Swift
//  UserDefaultsStorage.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import Synchronization
import TUICore

// MARK: - UserDefaults Storage (Apple Platforms)

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
    /// A storage backend that uses UserDefaults.
    ///
    /// Useful when running on Apple platforms with standard app conventions.
    ///
    /// Any number of these may stand over one defaults domain — the default
    /// store, a `store: .standard`, a `UserDefaults(suiteName:)` made afresh
    /// each time a view is — and a write through any one of them redraws the
    /// views that read the key through any other (see `sharedKeys`).
    ///
    /// A property-list value — a `Bool`, an `Int`, a `String` and the rest
    /// (`PropertyListValue`) — is kept as itself, as SwiftUI's `AppStorage`
    /// keeps it, so `UserDefaults`' own getters read what an `@AppStorage`
    /// wrote and an `@AppStorage` reads what they set. Any other `Codable`
    /// value is kept as its JSON encoding.
    public final class UserDefaultsStorage: StorageBackend, @unchecked Sendable {  // swiftlint:disable:this concurrency_escape
        /// The underlying UserDefaults.
        ///
        /// This one property is why the class is `@unchecked`: Foundation
        /// documents `UserDefaults` as thread-safe, and its SDK marks the type's
        /// `Sendable` conformance unavailable. It stays out of ``state``,
        /// because a write to it runs the key-value observers of whoever is
        /// watching the key, and they may read this store.
        private let defaults: UserDefaults

        private struct State {
            /// Every key this store has read or written: the bytes last seen
            /// for it, the value they decoded to, and its ``StoredKey``.
            var entries: [String: StoredEntry] = [:]

            /// The entry for `key`, made empty if there is none, on the key's
            /// shared ``StoredKey``.
            mutating func entry(_ key: String) -> StoredEntry {
                if let entry = entries[key] { return entry }
                let stored = UserDefaultsStorage.sharedKeys.withLock { keys in
                    if let stored = keys[key] { return stored }
                    let stored = StoredKey()
                    keys[key] = stored
                    return stored
                }
                let entry = StoredEntry(key: stored)
                entries[key] = entry
                return entry
            }
        }

        private let state = Mutex(State())

        /// One ``StoredKey`` per key, shared by every store of this type:
        /// readers of a key are registered on it whichever store they read
        /// the key through, so a write through any store reaches them all.
        ///
        /// By key alone, not by domain and key, because a `UserDefaults`
        /// cannot say which domain it is — it has no `suiteName` to read back
        /// — and two made for one suite are two objects, so neither the object
        /// nor its identity names the domain. Nor would the domain be enough:
        /// a suite's reads fall through to the app's own domain, so a write
        /// there can change what a suite's reader sees. A key of the same name
        /// in another domain shares the `StoredKey` too, which costs its
        /// readers a redraw that finds nothing changed, never a missed change.
        ///
        /// Taken only when a store first sees a key, inside its own lock;
        /// nothing takes the two the other way round.
        private static let sharedKeys = Lock<[String: StoredKey]>(initialState: [:])

        /// Creates a UserDefaults storage with standard defaults.
        public init() {
            self.defaults = .standard
        }

        /// Creates a UserDefaults storage with a custom suite.
        public init(suiteName: String?) {
            self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
        }

        /// Creates a UserDefaults storage over `defaults` — what
        /// `@AppStorage(_:store:)` and `defaultAppStorage(_:)` make of the
        /// `UserDefaults` they are given.
        ///
        /// - Parameter defaults: The defaults to read and write.
        public init(_ defaults: UserDefaults) {
            self.defaults = defaults
        }
    }

    // MARK: - Public API

    extension UserDefaultsStorage {
        /// The value stored for `key` as `T`, or `nil` when absent or
        /// undecodable, with the key's ``StoredKey``.
        ///
        /// The bytes are read from `UserDefaults` every time — another process
        /// may have written them — but decoded only when they are not the bytes
        /// the kept value came from (see `StoredEntry`).
        ///
        /// A decode failure is deliberately silent: reading a key whose stored
        /// shape no longer matches `T` — a type that gained a field between
        /// releases — falls back to the caller's default, which is
        /// ``AppStorage``'s defined behaviour rather than an error condition.
        /// This runs on the render path, so it also must not report per frame.
        /// Write failures, which are genuinely lossy, DO report (see
        /// ``store(_:forKey:)``).
        public func entry<T: Codable>(forKey key: String, as type: T.Type) -> (value: T?, key: StoredKey) {
            // A property-list value is read as itself, every time: there are no
            // bytes to keep a decoding of.
            if let stored = PropertyListValue.read(T.self, from: defaults, forKey: key) {
                return (stored, state.withLock { $0.entry(key).key })
            }
            let data = defaults.data(forKey: key)
            let (read, stored) = state.withLock { state -> (StoredValue<T?>, StoredKey) in
                let entry = state.entry(key)
                entry.reload(data)
                return (StoredValue(entry.value()), entry.key)
            }
            return (read.value, stored)
        }

        /// Stores `value` for `key`: as itself where `UserDefaults` keeps such
        /// a value (`PropertyListValue`), JSON-encoded otherwise.
        ///
        /// An encode failure is reported through ``StorageDiagnostics``,
        /// unlike the read path: a value that cannot be written is data the
        /// user expected to keep, so it is worth surfacing.
        public func store<T: Codable>(_ value: T, forKey key: String) -> StoredKey {
            if PropertyListValue.write(value, to: defaults, forKey: key) {
                return state.withLock { state in
                    let entry = state.entry(key)
                    entry.clear()
                    return entry.key
                }
            }
            let data: Data
            do {
                data = try JSONEncoder().encode(value)
            } catch {
                StorageDiagnostics.report(
                    StorageFailure(operation: .encode, key: key, underlying: error))
                return state.withLock { $0.entry(key).key }
            }
            defaults.set(data, forKey: key)
            let crossing = StoredValue(value)
            return state.withLock { state in
                let entry = state.entry(key)
                entry.set(crossing.value, encoded: data)
                return entry.key
            }
        }

        /// Removes any value stored for `key`. A key that was never set is
        /// not an error.
        ///
        /// Returns the key's shared ``StoredKey`` even where this store has
        /// never seen the key: readers may be waiting on it through another.
        public func remove(forKey key: String) -> StoredKey? {
            defaults.removeObject(forKey: key)
            return state.withLock { state in
                guard let entry = state.entries[key] else { return Self.sharedKeys.withLock { $0[key] } }
                entry.clear()
                return entry.key
            }
        }

        /// Asks `UserDefaults` to flush pending writes.
        ///
        /// Rarely needed — the system persists on its own schedule — but a
        /// terminal app can be killed by a signal between frames, so the app
        /// lifecycle calls it at shutdown.
        public func synchronize() {
            defaults.synchronize()
        }
    }

    // MARK: - Property-list values

    /// An `Optional`, seen through its type: what a stored optional's `nil`
    /// removes, and what its wrapped type keeps.
    private protocol PropertyListOptional {
        /// The wrapped value, or `nil`.
        var wrappedPropertyListValue: Any? { get }
        /// The wrapped type.
        static var wrappedPropertyListType: Any.Type { get }
    }

    extension Optional: PropertyListOptional {
        var wrappedPropertyListValue: Any? { map { $0 as Any } }
        static var wrappedPropertyListType: Any.Type { Wrapped.self }
    }

    /// The values `UserDefaults` keeps as themselves, as SwiftUI's
    /// `AppStorage` keeps them: a `Bool`, an `Int`, a `Double`, a `String`, a
    /// `Date`, `Data`, a `URL` (through `UserDefaults`' own URL methods), a
    /// type whose raw value is an `Int` or a `String` (as its raw value), and
    /// the optionals of these, whose `nil` removes the key. So
    /// `UserDefaults.standard.bool(forKey:)` reads what an `@AppStorage` of a
    /// `Bool` wrote, as it does under SwiftUI. Any other `Codable` value — a
    /// TUI extension — is kept as its JSON encoding.
    enum PropertyListValue {
        /// Whether `type` is kept as itself.
        static func isPropertyList(_ type: Any.Type) -> Bool {
            if let optional = type as? any PropertyListOptional.Type {
                return isPropertyList(optional.wrappedPropertyListType)
            }
            if let raw = type as? any RawRepresentable.Type { return rawIsPropertyList(raw) }
            return type == Bool.self || type == Int.self || type == Double.self || type == String.self
                || type == Date.self || type == Data.self || type == URL.self
        }

        private static func rawIsPropertyList<R: RawRepresentable>(_: R.Type) -> Bool {
            R.RawValue.self == Int.self || R.RawValue.self == String.self
        }

        /// Writes `value` as itself — removing the key for an optional's
        /// `nil` — or returns `false` where `T` is not kept as itself.
        static func write<T>(_ value: T, to defaults: UserDefaults, forKey key: String) -> Bool {
            guard isPropertyList(T.self) else { return false }
            switch object(value) {
            case nil: defaults.removeObject(forKey: key)
            case let url as URL: defaults.set(url, forKey: key)
            case let object?: defaults.set(object, forKey: key)
            }
            return true
        }

        /// The object `UserDefaults` keeps for `value`: its raw value for a
        /// raw-representable, the wrapped value's for an optional, `nil` for
        /// an optional's `nil`.
        private static func object(_ value: Any) -> Any? {
            if let optional = value as? any PropertyListOptional {
                return optional.wrappedPropertyListValue.flatMap(object)
            }
            if let raw = value as? any RawRepresentable { return raw.rawValue }
            return value
        }

        /// The value stored for `key` as `T` — `.some(nil)` where it is
        /// absent or of another type — or `nil` where `T` is not kept as
        /// itself.
        static func read<T>(_: T.Type, from defaults: UserDefaults, forKey key: String) -> T?? {
            guard isPropertyList(T.self) else { return nil }
            // Absent is `nil`, for an optional `T` too: cast, a missing
            // value would become an optional's `nil` and stand in for the
            // caller's default.
            guard let found = value(T.self, from: defaults, forKey: key) else { return .some(nil) }
            return .some(found as? T)
        }

        /// The value stored for `key` as `type`, or `nil`.
        private static func value(_ type: Any.Type, from defaults: UserDefaults, forKey key: String) -> Any? {
            if let optional = type as? any PropertyListOptional.Type {
                return value(optional.wrappedPropertyListType, from: defaults, forKey: key)
            }
            if type == URL.self { return defaults.url(forKey: key) }
            guard let object = defaults.object(forKey: key) else { return nil }
            if let raw = type as? any RawRepresentable.Type { return fromRawValue(raw, object) }
            switch type {
            case is Bool.Type: return object as? Bool
            case is Int.Type: return object as? Int
            case is Double.Type: return object as? Double
            case is String.Type: return object as? String
            case is Date.Type: return object as? Date
            case is Data.Type: return object as? Data
            default: return nil
            }
        }

        private static func fromRawValue<R: RawRepresentable>(_: R.Type, _ object: Any) -> Any? {
            (object as? R.RawValue).flatMap(R.init(rawValue:))
        }
    }

// MARK: - UserDefaults Storage (Linux)

#elseif os(Linux)
    /// A storage backend that emulates UserDefaults on Linux.
    ///
    /// Uses a JSON file at `~/.local/share/[appName]/UserDefaults.json` to store data,
    /// following the XDG Base Directory Specification.
    public final class UserDefaultsStorage: StorageBackend {
        /// The underlying file storage.
        private let storage: JSONFileStorage

        /// The suite name (nil for standard defaults).
        private let suiteName: String?

        /// Creates a UserDefaults-compatible storage with standard defaults.
        public init() {
            self.suiteName = nil
            self.storage = Self.createStorage(suiteName: nil)
        }

        /// Creates a UserDefaults-compatible storage with a custom suite.
        ///
        /// On Linux, each suite gets its own JSON file.
        public init(suiteName: String?) {
            self.suiteName = suiteName
            self.storage = Self.createStorage(suiteName: suiteName)
        }
    }

    // MARK: - Public API

    extension UserDefaultsStorage {
        /// The value stored for `key` as `T`, from the JSON file standing in
        /// for `UserDefaults` on this platform, with the key's ``StoredKey``.
        public func entry<T: Codable>(forKey key: String, as type: T.Type) -> (value: T?, key: StoredKey) {
            storage.entry(forKey: key, as: T.self)
        }

        /// Stores `value` for `key` in the backing file.
        public func store<T: Codable>(_ value: T, forKey key: String) -> StoredKey {
            storage.store(value, forKey: key)
        }

        /// Removes any value stored for `key`.
        public func remove(forKey key: String) -> StoredKey? {
            storage.remove(forKey: key)
        }

        /// Flushes pending writes to the backing file.
        public func synchronize() {
            storage.synchronize()
        }

        // MARK: - UserDefaults-compatible convenience methods

        /// Returns the string value for the given key.
        public func string(forKey key: String) -> String? {
            value(forKey: key)
        }

        /// Returns the integer value for the given key.
        public func integer(forKey key: String) -> Int {
            value(forKey: key) ?? 0
        }

        /// Returns the double value for the given key.
        public func double(forKey key: String) -> Double {
            value(forKey: key) ?? 0.0
        }

        /// Returns the boolean value for the given key.
        public func bool(forKey key: String) -> Bool {
            value(forKey: key) ?? false
        }

        /// Returns the data value for the given key.
        public func data(forKey key: String) -> Data? {
            value(forKey: key)
        }

        /// Returns the array value for the given key.
        public func array<T: Codable>(forKey key: String) -> [T]? {
            value(forKey: key)
        }

        /// Returns the dictionary value for the given key.
        public func dictionary<K: Codable & Hashable, V: Codable>(forKey key: String) -> [K: V]? {
            value(forKey: key)
        }

        /// Sets a string value for the given key.
        public func set(_ value: String?, forKey key: String) {
            if let value {
                setValue(value, forKey: key)
            } else {
                removeValue(forKey: key)
            }
        }

        /// Sets an integer value for the given key.
        public func set(_ value: Int, forKey key: String) {
            setValue(value, forKey: key)
        }

        /// Sets a double value for the given key.
        public func set(_ value: Double, forKey key: String) {
            setValue(value, forKey: key)
        }

        /// Sets a boolean value for the given key.
        public func set(_ value: Bool, forKey key: String) {
            setValue(value, forKey: key)
        }

        /// Sets a data value for the given key.
        public func set(_ value: Data?, forKey key: String) {
            if let value {
                setValue(value, forKey: key)
            } else {
                removeValue(forKey: key)
            }
        }
    }

    // MARK: - Private Helpers

    extension UserDefaultsStorage {
        fileprivate static func createStorage(suiteName: String?) -> JSONFileStorage {
            let appName = sanitizedProcessName(ProcessInfo.processInfo.processName)

            // Use XDG Base Directory: ~/.local/share/[appName]/
            //
            // "If $XDG_DATA_HOME is either not set or empty, a default equal to
            // $HOME/.local/share should be used" — the spec's wording, and the
            // empty half of it matters: `URL(fileURLWithPath: "")` is a
            // RELATIVE path, so an empty variable (which shells produce readily
            // — `XDG_DATA_HOME= app`, or an unset variable exported anyway) put
            // the app's saved state in whatever directory it happened to be
            // launched from.
            let dataHome: URL
            if let xdgDataHome = ProcessInfo.processInfo.environment["XDG_DATA_HOME"],
                !xdgDataHome.isEmpty
            {
                dataHome = URL(fileURLWithPath: xdgDataHome)
            } else {
                dataHome = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".local")
                    .appendingPathComponent("share")
            }

            let appDir = dataHome.appendingPathComponent(appName)

            // Create directory if needed
            do {
                try FileManager.default.createDirectory(
                    at: appDir, withIntermediateDirectories: true)
            } catch {
                StorageDiagnostics.report(
                    StorageFailure(
                        operation: .createDirectory, path: appDir.path, underlying: error))
            }

            // Use suite name in filename if provided
            let filename: String
            if let suite = suiteName {
                filename = "UserDefaults-\(suite).json"
            } else {
                filename = "UserDefaults.json"
            }

            let fileURL = appDir.appendingPathComponent(filename)
            return JSONFileStorage(fileURL: fileURL)
        }
    }
#endif
