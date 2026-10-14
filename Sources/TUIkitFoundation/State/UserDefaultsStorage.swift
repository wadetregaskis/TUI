//  🖥️ TUIkit — Terminal UI Kit for Swift
//  UserDefaultsStorage.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import TUIkitCore

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
    public final class UserDefaultsStorage: StorageBackend, @unchecked Sendable {
        /// The underlying UserDefaults.
        private let defaults: UserDefaults

        /// Every key this store has read or written, guarded by `lock`: the
        /// bytes last seen for it, the value they decoded to, and its
        /// ``StoredKey``.
        private var entries: [String: StoredEntry] = [:]

        /// Guards `entries`.
        private let lock = NSLock()

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
        /// Taken only when a store first sees a key, inside its own `lock`;
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
            let data = defaults.data(forKey: key)
            lock.lock()
            defer { lock.unlock() }
            let entry = entryLocked(key)
            entry.reload(data)
            return (entry.value(as: T.self), entry.key)
        }

        /// Stores `value` for `key`, JSON-encoded.
        ///
        /// An encode failure is reported through ``StorageDiagnostics``,
        /// unlike the read path: a value that cannot be written is data the
        /// user expected to keep, so it is worth surfacing.
        public func store<T: Codable>(_ value: T, forKey key: String) -> StoredKey {
            let data: Data
            do {
                data = try JSONEncoder().encode(value)
            } catch {
                StorageDiagnostics.report(
                    StorageFailure(operation: .encode, key: key, underlying: error))
                lock.lock()
                defer { lock.unlock() }
                return entryLocked(key).key
            }
            defaults.set(data, forKey: key)
            lock.lock()
            defer { lock.unlock() }
            let entry = entryLocked(key)
            entry.set(value, encoded: data)
            return entry.key
        }

        /// Removes any value stored for `key`. A key that was never set is
        /// not an error.
        ///
        /// Returns the key's shared ``StoredKey`` even where this store has
        /// never seen the key: readers may be waiting on it through another.
        public func remove(forKey key: String) -> StoredKey? {
            defaults.removeObject(forKey: key)
            lock.lock()
            defer { lock.unlock() }
            guard let entry = entries[key] else { return Self.sharedKeys.withLock { $0[key] } }
            entry.clear()
            return entry.key
        }

        /// The entry for `key`, made empty if there is none, on the key's
        /// shared ``StoredKey`` (caller holds `lock`).
        private func entryLocked(_ key: String) -> StoredEntry {
            if let entry = entries[key] { return entry }
            let stored = Self.sharedKeys.withLock { keys in
                if let stored = keys[key] { return stored }
                let stored = StoredKey()
                keys[key] = stored
                return stored
            }
            let entry = StoredEntry(key: stored)
            entries[key] = entry
            return entry
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

// MARK: - UserDefaults Storage (Linux)

#elseif os(Linux)
    /// A storage backend that emulates UserDefaults on Linux.
    ///
    /// Uses a JSON file at `~/.local/share/[appName]/UserDefaults.json` to store data,
    /// following the XDG Base Directory Specification.
    public final class UserDefaultsStorage: StorageBackend, @unchecked Sendable {
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
