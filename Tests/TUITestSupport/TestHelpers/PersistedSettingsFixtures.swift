//  🖥️ TUI — A Terminal UI framework for Swift
//  PersistedSettingsFixtures.swift
//
//  The settings files the persisted-settings compatibility tests read: one as
//  TUI writes it today, one as a later TUI might, both committed under
//  `__Fixtures__/PersistedSettings`.
//
//  Created by Wade Tregaskis
//  License: MIT

// Built for tests only: a plain `swift build -c release` compiles this file empty (see TUITestSupport in Package.swift).
#if TUI_TEST_SUPPORT && canImport(Testing)

import Foundation

@testable import TUIFoundation

/// The settings files every key TUI itself keeps is read from in the
/// compatibility tests (the API stability policy's persisted state: an app
/// built with any 1.n reads what any 1.m wrote, older or newer).
///
/// - `settings.json`: today's `settings.json` (and Linux's `UserDefaults.json`,
///   the same format), holding a value for every key TUI keeps: the file
///   panels' view mode, preview, hidden files, size and folder, a customized
///   toolbar, the colour picker's two, and `@SceneStorage`'s shared key, a
///   session's key and the session ledger. NEVER regenerate it to make a test
///   pass: it is what apps already in use have on disk, and a change that
///   cannot read it breaks them.
/// - `settings-newer.json`: what a later TUI might leave there — a new case of
///   an enum stored by raw value, a size out of range and one retyped, a
///   record with a field this one doesn't know or without one it does, a key
///   it has never heard of, and values that are not this format's base64
///   strings at all. A reader must take what it knows and leave the rest.
///
/// Read by path (`#filePath`), as the golden snapshots are, so they are
/// excluded from the build rather than bundled as resources.
package enum PersistedSettingsFixtures {
    /// The session `@SceneStorage`'s session key and ledger entry are for.
    package static let session = "fixture-session"

    /// `scene.page`'s key for ``session``: `scene@`, the session's digest, and
    /// the key after `scene`.
    package static let sessionPageKey = "scene@dbf4e7add29e7a7f.page"

    /// The committed fixture `name`.
    package static func url(_ name: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // TestHelpers/
            .deletingLastPathComponent()  // TUITestSupport/
            .appendingPathComponent("__Fixtures__/PersistedSettings")
            .appendingPathComponent(name)
    }

    /// A scratch copy of fixture `name`, alone in a directory of its own for
    /// the caller to remove, so a write never reaches the committed file.
    package static func scratchCopy(_ name: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tui.settings-fixture.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let copy = directory.appendingPathComponent("settings.json")
        try FileManager.default.copyItem(at: url(name), to: copy)
        return copy
    }

    /// Runs `body` with a store loaded from a ``scratchCopy(_:)`` of fixture
    /// `name`, and the copy's location.
    package static func withStore(
        _ name: String, _ body: (JSONFileStorage, URL) throws -> Void
    ) throws {
        let copy = try scratchCopy(name)
        defer { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) }
        let store = JSONFileStorage(fileURL: copy)
        // A write queues its save, which could land after the removal above.
        defer { store.synchronize() }
        try body(store, copy)
    }

    /// The top level of a settings file as JSON: each key's base64 string, or
    /// whatever a later TUI put there.
    package static func topLevel(of file: URL) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any] ?? [:]
    }

    /// The JSON a settings file holds for `key`, decoded from its base64
    /// string and written out again with sorted keys and no spacing: so two
    /// files compare equal whatever order or spacing their writers used.
    package static func storedJSON(_ key: String, in file: URL) throws -> String? {
        guard let base64 = try topLevel(of: file)[key] as? String, let data = Data(base64Encoded: base64) else {
            return nil
        }
        let value = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        let canonical = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
        return String(bytes: canonical, encoding: .utf8)
    }
}

#endif
