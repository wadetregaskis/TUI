//  🖥️ TUI — A Terminal UI framework for Swift
//  DefaultAppStorage.swift
//
//  `defaultAppStorage(_:)`: the store an `@AppStorage` that names none reads
//  and writes, set for a subtree (decisions A18).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - The Environment Value

/// The store `defaultAppStorage(_:)` set: what an ``AppStorage`` that names no
/// store of its own reads and writes beneath it.
///
/// Equatable, so that setting one does not turn off the memos beneath it (an
/// environment value that cannot be compared does), and equal only where the
/// two read and write the same thing: the same `UserDefaults`, which the
/// `UserDefaults` spelling makes a new store over each time it is written, or
/// else the same store object. A store that is not an object never compares
/// equal, so a subtree under one is drawn afresh each frame.
package struct DefaultAppStorage: Equatable, Sendable {
    /// The store.
    package let store: any StorageBackend

    /// What decides equality: the object the store reads and writes through,
    /// or `nil` for a store that is not an object.
    private let identity: ObjectIdentifier?

    /// The store `store`.
    package init(_ store: any StorageBackend) {
        self.store = store
        self.identity = type(of: store) is AnyObject.Type ? ObjectIdentifier(store as AnyObject) : nil
    }

    #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        /// A store over `defaults`, equal to any other over the same object.
        package init(_ defaults: UserDefaults) {
            self.store = UserDefaultsStorage(defaults)
            self.identity = ObjectIdentifier(defaults)
        }
    #endif

    /// Whether the two read and write through one object. Sound against an
    /// address coming back: the store holds that object, and the value an
    /// equal one is compared with is kept until one is not equal.
    package static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.identity != nil && lhs.identity == rhs.identity
    }
}

private struct DefaultAppStorageKey: EnvironmentKey {
    static let defaultValue: DefaultAppStorage? = nil
}

extension EnvironmentValues {
    /// The store an ``AppStorage`` that names none reads and writes, or `nil`
    /// for ``StorageDefaults/backend``.
    package var defaultAppStorage: DefaultAppStorage? {
        get { self[DefaultAppStorageKey.self] }
        set { self[DefaultAppStorageKey.self] = newValue }
    }
}

// MARK: - Public Modifiers

extension View {
    #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        /// The default store used by ``AppStorage`` contained within the view
        /// — mirrors SwiftUI's `defaultAppStorage(_:)`.
        ///
        /// An `@AppStorage` that names no store reads and writes the store
        /// set nearest above it; one that names a store keeps it. With none
        /// set, it uses ``StorageDefaults/backend``.
        ///
        /// Pass a `UserDefaults` that lives as long as the view does — `.standard`,
        /// or one kept in a `let` — rather than making one in `body`: a new
        /// object each time is a new store each time, which is correct but
        /// redraws the whole subtree.
        ///
        /// - Parameter store: The user defaults to use as the default store
        ///   for `AppStorage`.
        /// - Returns: A view whose `@AppStorage` properties use `store`.
        public func defaultAppStorage(_ store: UserDefaults) -> some View {
            environment(\.defaultAppStorage, DefaultAppStorage(store))
        }
    #endif

    /// The default store used by ``AppStorage`` contained within the view: a
    /// TUI ``StorageBackend``, the form available on every platform.
    ///
    /// As with the `UserDefaults` form on Apple platforms, an `@AppStorage`
    /// that names no store uses the one set nearest above it. Pass a store
    /// that lives as long as the view does.
    ///
    /// - Parameter store: The store to use as the default for `AppStorage`.
    /// - Returns: A view whose `@AppStorage` properties use `store`.
    public func defaultAppStorage(_ store: any StorageBackend) -> some View {
        environment(\.defaultAppStorage, DefaultAppStorage(store))
    }
}
