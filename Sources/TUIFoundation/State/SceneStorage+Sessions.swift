//  🖥️ TUI — A Terminal UI framework for Swift
//  SceneStorage+Sessions.swift
//
//  `@SceneStorage` per terminal session: the session's keys, and the ledger
//  that bounds how many sessions a store keeps.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation

// MARK: - The Session's Keys

/// Where a ``SceneStorage`` keeps its values for one terminal session, and
/// the record of the sessions a store holds, which bounds them.
///
/// A property keeps two copies of each value: the session's, under
/// ``key(_:session:)``, and the one last saved from any session, under its
/// plain `scene.` key. It reads the session's, else the last saved, else its
/// default. See
/// `Documentation/Historical/State and dynamic properties/Scene storage per terminal session.md`.
enum SceneStorageSessions {
    /// The key a session keeps `scopedKey` (`scene.` and on) under:
    /// `scene@`, a fixed-length digest of the session and the rest of the
    /// key, so `scene@0123456789abcdef.viewer#2.tab`.
    ///
    /// A digest rather than the session itself, which is a terminal's own
    /// string (a path, a UUID, `w0t0p0:…`): fixed in length, so no session's
    /// characters can run into the key after it, and no terminal's
    /// identifiers are written into the app's preferences.
    static func key(_ scopedKey: String, session: String) -> String {
        "scene@" + digest(session) + scopedKey.dropFirst(prefixLength)
    }

    /// The length of `scene`, which ``key(_:session:)`` replaces.
    private static let prefixLength = "scene".count

    /// FNV-1a over the session's UTF-8, as sixteen hex digits: the same from
    /// run to run and platform to platform, as `Hasher`, seeded per process,
    /// is not. Not a defence against anyone choosing a collision, which
    /// would only mix two of one user's own sessions.
    private static func digest(_ session: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in session.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x0000_0100_0000_01b3
        }
        let hex = String(hash, radix: 16)
        return String(repeating: "0", count: 16 - hex.count) + hex
    }

    // MARK: - The Ledger

    /// The key the ledger is kept under. `scene@` and no digest, so no
    /// session's keys can be it.
    static let ledgerKey = "scene@sessions"

    /// How long a session that wrote nothing is kept: 30 days, longer than a
    /// window is left alone and still come back to, short enough that a
    /// terminal's ended sessions do not pile up.
    ///
    /// The only bound: there is no cap on how many sessions a store keeps
    /// (the owner, 2026-11-08: "let's not put any limit on how many sessions
    /// there can be. If it somehow becomes a problem, such as for performance,
    /// then we will address that as it rises").
    static let sessionLifetime: TimeInterval = 30 * 24 * 60 * 60

    /// How stale a session's last-written stamp may grow before a write
    /// renews it: an hour. A write that adds no key and finds a fresher stamp
    /// leaves the ledger alone, so a slider bound to scene storage costs one
    /// ledger read a tick, not a ledger write.
    static let stampInterval: TimeInterval = 60 * 60

    /// One session's record: when it last wrote, and the keys it wrote, which
    /// go when it does — a store cannot list its keys.
    struct Record: Codable, Equatable {
        /// When the session last wrote, as seconds since 1970.
        var lastWritten: TimeInterval
        /// Every key the session has written (``key(_:session:)``).
        var keys: [String]
    }

    /// Notes in `store`'s ledger that `session` wrote `key` at `now`, and
    /// drops the sessions that wrote nothing for ``sessionLifetime``, with
    /// their keys.
    ///
    /// Read and written past observation: no view reads the ledger.
    static func noteWrite(of key: String, session: String, in store: any StorageBackend, now: Date) {
        var ledger = store.entry(forKey: ledgerKey, as: [String: Record].self).value ?? [:]
        let stamp = now.timeIntervalSince1970
        var record = ledger[session] ?? Record(lastWritten: stamp, keys: [])
        let isNewKey = !record.keys.contains(key)
        guard ledger[session] == nil || isNewKey || stamp - record.lastWritten >= stampInterval else { return }
        if isNewKey { record.keys.append(key) }
        record.lastWritten = stamp
        ledger[session] = record

        let kept = Set(ledger.filter { stamp - $0.value.lastWritten <= sessionLifetime }.keys)
        for (dropped, record) in ledger where !kept.contains(dropped) {
            for key in record.keys { store.removeValue(forKey: key) }
            ledger[dropped] = nil
        }
        _ = store.store(ledger, forKey: ledgerKey)
    }
}

// MARK: - The Environment Value

private struct SceneStorageSessionKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// The terminal session the app runs in (`TerminalSession`), whose own
    /// copies a ``SceneStorage`` reads first and writes beside the last
    /// saved, or `nil` for none: only the last saved, as over a plain ssh
    /// connection. Set at the root by the app's run loop, and nowhere else,
    /// so a headless run or a test never depends on the terminal it was
    /// started from.
    package var sceneStorageSession: String? {
        get { self[SceneStorageSessionKey.self] }
        set { self[SceneStorageSessionKey.self] = newValue }
    }
}
