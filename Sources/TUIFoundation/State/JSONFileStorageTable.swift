//  🖥️ TUI — A Terminal UI framework for Swift
//  JSONFileStorageTable.swift
//
//  Created by LAYERED.work
//  License: MIT

import Foundation
import Synchronization

/// One ``JSONFileStorage`` for each file, held weakly, handed to every store
/// that asks for that file.
///
/// What `UserDefaultsStorage` stands on where a suite is a JSON file of TUI's
/// own (Linux, WebAssembly and Windows; `UserDefaultsStorage.suiteFiles`).
/// `@AppStorage("theme", store: UserDefaultsStorage(suiteName: "prefs"))`
/// makes a store with every view, and each one used to load the file and keep
/// a copy of its own: a write through one reached another only when that one
/// loaded the file again, its readers heard nothing, and the two saves raced
/// (bug hunt FENV-2, 2026-11-20). Through this table every store over one file
/// stands on one backing — one copy of the file, one save queue, one
/// ``StoredKey`` for each key, one scene-state store — so a write through any
/// of them is read through every other at once and redraws whoever reads the
/// key through any of them, as two `UserDefaults` over one suite do on Apple
/// platforms.
///
/// Held weakly, so a backing goes when its last store does, saving what it
/// has not saved as it goes (``JSONFileStorage``'s `deinit`); the next store
/// over that file loads it afresh. An entry whose backing has gone is dropped
/// the next time a backing is added, so the table never holds more than the
/// files whose stores are alive, and one entry for each that has gone since.
///
/// Keyed by the file's path, standardised (`.` and `..` resolved), and by
/// nothing else: two stores over one file are one store's worth of state,
/// whoever made them. Two names for one file that the path does not show —
/// a symbolic link, or on Windows a name in another case — keep a backing
/// each, as every store did before.
///
/// One narrow gap is left: a store asked for on one thread while the last
/// store over the file is being freed on another gets a new backing, which may
/// load the file before the freed one's unsaved writes reach it. On one
/// thread, as views are made and let go, the freed backing has saved before
/// the next is made.
final class JSONFileStorageTable: Sendable {
    /// One file's backing, held weakly.
    private struct Held {
        weak let store: JSONFileStorage?
    }

    /// Each file's backing, by its key (``key(of:)``).
    private let held = Mutex<[String: Held]>([:])

    /// An empty table: a test's, or `UserDefaultsStorage.suiteFiles`.
    init() {}

    /// The backing for `fileURL`: the one every live store over that file
    /// stands on, or a new one, loaded from the file, if none is alive.
    ///
    /// The new one is made outside the lock: loading the file can report a
    /// failure to the app's handler (``StorageDiagnostics``), which may ask
    /// for a store itself, and the lock cannot be taken twice. Two threads
    /// that both find none make one each, and the second to come back takes
    /// the first's; its own, which has nothing unsaved, goes without a write.
    ///
    /// - Parameters:
    ///   - fileURL: The file the backing reads and writes.
    ///   - prepare: What to do before a backing is made, such as making its
    ///     folder; not run when one is found.
    func store(at fileURL: URL, preparing prepare: () -> Void = {}) -> JSONFileStorage {
        let key = Self.key(of: fileURL)
        if let found = held.withLock({ $0[key]?.store }) { return found }
        prepare()
        let made = JSONFileStorage(fileURL: fileURL)
        return held.withLock { held in
            if let found = held[key]?.store { return found }
            held = held.filter { $0.value.store != nil }
            held[key] = Held(store: made)
            return made
        }
    }

    /// How many files the table has an entry for, alive or not: for a test
    /// that entries are dropped.
    var entryCount: Int {
        held.withLock { $0.count }
    }

    /// The table's key for `fileURL`: its path, standardised.
    private static func key(of fileURL: URL) -> String {
        fileURL.standardizedFileURL.path
    }
}
