//  🖥️ TUI — A Terminal UI framework for Swift
//  UserDefaultsStorage+Watching.swift
//
//  What tells the views that read a key of a `UserDefaults` that it changed,
//  when the change was not made through TUI: a settings model that writes
//  `UserDefaults.standard` itself, another process's `defaults write`.
//
//  Created by Wade Tregaskis
//  License: MIT

#if canImport(Darwin)
    import Foundation
    import Synchronization

    /// Watches the keys ``UserDefaultsStorage``s have read through one
    /// `UserDefaults`, and announces each one's shared ``StoredKey`` when its
    /// value changes, however it was changed: SwiftUI's `AppStorage` redraws
    /// its view on any change to its default, and a view here was redrawn
    /// only by a write through a store (bug hunt FENV-4, 2026-11-20).
    ///
    /// One for each `UserDefaults` object, kept on it as an associated object,
    /// so it lives exactly as long as the object it reads, however many stores
    /// stand over it: `.standard`'s for the life of the process, a suite's
    /// made afresh in a view's initialiser while a view value holds it.
    ///
    /// **Key-value observing where it can, the notification where it
    /// cannot.** KVO names the key that changed, costs about a microsecond to
    /// register a key and nothing at a write to any other, and hears another
    /// process's write even with no run loop running, as TUI's async `main`
    /// runs none; `UserDefaults.didChangeNotification` names no key, and is
    /// not posted for another process's write without a run loop. Both are
    /// posted for a write through any `UserDefaults` of the domain, on the
    /// writing thread, before the write returns. But KVO reads its key as a
    /// path: a key with a `.` in it, as `@AppStorage("editor.fontSize")` has,
    /// observes `editor`, then `fontSize` on whatever `editor` holds, and
    /// Foundation raises an exception that ends the app as soon as anything
    /// writes `editor`; an empty key raises as it is registered, and one that
    /// begins with `@` is never announced (all measured, macOS 15.8,
    /// 2026-11-24). So such a key is watched through the notification, for
    /// every object (`object: nil`, since it names no domain), and found
    /// changed by comparing its value with the one seen before: a read of
    /// each such key at every write in the process, and only once one is
    /// watched.
    final class UserDefaultsWatcher: NSObject {
        /// The defaults whose keys are watched; weak, since they hold this.
        private weak let defaults: UserDefaults?

        /// What changes, behind one lock.
        private struct State {
            /// Each key watched through KVO, and its shared ``StoredKey``.
            var observed: [String: StoredKey] = [:]
            /// Each key watched through the notification: its ``StoredKey``,
            /// and the value it last held.
            var compared: [String: (stored: StoredKey, value: PropertyListObject)] = [:]

            func isWatched(_ key: String) -> Bool {
                observed[key] != nil || compared[key] != nil
            }
        }

        private let state = Mutex(State())

        /// The association's key: the class object's address, unique to this
        /// class and fixed, as the key must be.
        private static var address: Int { Int(bitPattern: ObjectIdentifier(UserDefaultsWatcher.self)) }

        private init(_ defaults: UserDefaults) {
            self.defaults = defaults
        }

        /// The watcher of `defaults`, made the first time it is asked for.
        static func of(_ defaults: UserDefaults) -> UserDefaultsWatcher {
            // `unsafe`: the runtime's API takes a raw pointer, used here only
            // as a name, never read through.
            let key = unsafe UnsafeRawPointer(bitPattern: address)!
            // The object's own lock, so two threads that both find none do not
            // make one each, the second dropping the first's keys.
            objc_sync_enter(defaults)
            defer { objc_sync_exit(defaults) }
            if let found = unsafe objc_getAssociatedObject(defaults, key) as? UserDefaultsWatcher { return found }
            let made = UserDefaultsWatcher(defaults)
            unsafe objc_setAssociatedObject(defaults, key, made, .OBJC_ASSOCIATION_RETAIN)
            return made
        }

        /// Whether KVO can watch `key`: not empty, no `.`, not begun with `@`.
        static func isObservable(_ key: String) -> Bool {
            !key.isEmpty && !key.hasPrefix("@") && !key.utf8.contains(UInt8(ascii: "."))
        }

        /// Watches `key`, announcing a change to it through `stored`.
        ///
        /// Called by a store the first time it sees a key, and never with its
        /// own lock held: registering reads the key, and `UserDefaults` may
        /// run this watcher while it does.
        func watch(_ key: String, announcing stored: StoredKey) {
            guard let defaults, !state.withLock({ $0.isWatched(key) }) else { return }
            if Self.isObservable(key) {
                let isNew = state.withLock { state in
                    guard !state.isWatched(key) else { return false }
                    state.observed[key] = stored
                    return true
                }
                guard isNew else { return }
                // `unsafe`: the context is a raw pointer, and none is passed.
                unsafe defaults.addObserver(self, forKeyPath: key, options: [], context: nil)
                return
            }
            let value = PropertyListObject(defaults.object(forKey: key))
            let isFirst = state.withLock { state in
                guard !state.isWatched(key) else { return false }
                state.compared[key] = (stored, value)
                return state.compared.count == 1
            }
            guard isFirst else { return }
            // A selector rather than a block: the center holds the observer
            // weakly and drops it when it goes, so nothing need be removed;
            // and a block would be `@Sendable`, which `UserDefaults` is not.
            NotificationCenter.default.addObserver(
                self, selector: #selector(defaultsDidChange(_:)), name: UserDefaults.didChangeNotification, object: nil)
        }

        // A key this watcher observes changed. Every observation this object
        // holds is one it made (the class is final, and registers itself
        // alone), so no context tells them apart, and none is passed on. The
        // block-based API takes a Swift key path to an `@objc dynamic`
        // property, and a default's key is a string.
        // swiftlint:disable:next block_based_kvo
        override func observeValue(
            forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?
        ) {
            guard let keyPath, let stored = state.withLock({ $0.observed[keyPath] }) else { return }
            Self.announce([stored])
        }

        /// Compares each key watched through the notification with the value
        /// it held, and announces those that changed.
        ///
        /// The values are read outside the lock: the notification is posted
        /// inside `UserDefaults`' own write, and reading takes its locks.
        @objc private func defaultsDidChange(_: Notification) {
            guard let defaults else { return }
            let keys = state.withLock { Array($0.compared.keys) }
            let now = keys.map { PropertyListObject(defaults.object(forKey: $0)) }
            let changed = state.withLock { state -> [StoredKey] in
                var changed: [StoredKey] = []
                for (key, value) in zip(keys, now) {
                    guard let held = state.compared[key], held.value != value else { continue }
                    state.compared[key]?.value = value
                    changed.append(held.stored)
                }
                return changed
            }
            Self.announce(changed)
        }

        /// Announces `keys` on the main actor, where views are invalidated: at
        /// once when the write was made there — an event handler's, a
        /// model's — so it is drawn in the frame the handler asked for; else
        /// on its next turn.
        private static func announce(_ keys: [StoredKey]) {
            guard !keys.isEmpty else { return }
            if Thread.isMainThread {
                MainActor.assumeIsolated { didChange(keys) }
            } else {
                Task { @MainActor in didChange(keys) }
            }
        }

        @MainActor
        private static func didChange(_ keys: [StoredKey]) {
            for key in keys { key.didChange() }
        }
    }

    /// A value as `UserDefaults` keeps it, as a binary property list's bytes,
    /// or nothing.
    ///
    /// Bytes rather than the object: Foundation's property-list objects are
    /// immutable, but the SDK does not mark them `Sendable`, and a value held
    /// behind a `Mutex` must be. Two bytes apart where the values are equal —
    /// a dictionary's keys in another order — cost a redraw that finds nothing
    /// new, never a missed change.
    private struct PropertyListObject: Equatable, Sendable {
        let bytes: Data?

        init(_ object: Any?) {
            bytes = object.flatMap { try? PropertyListSerialization.data(fromPropertyList: $0, format: .binary, options: 0) }
        }
    }
#endif
