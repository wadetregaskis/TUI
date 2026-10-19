//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SceneStoragePerWindowTests.swift
//
//  `@SceneStorage` is one per window (lane O9): each window the app opens
//  keeps its values under a namespace of its own, the window opened at launch
//  under `scene.` as before, a `Window`'s under its identifier, and a group's
//  windows past the first under their ordinal too.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

// MARK: - Fixtures

/// The store every window's scene storage is kept in, reachable from views.
private final class StorageProbe: @unchecked Sendable {
    static let shared = StorageProbe()
    var store = MockStorageBackend()
}

/// A window's content: its scene-stored tab, which its button moves on.
private struct TabPage: View {
    @SceneStorage("tab", store: StorageProbe.shared.store) private var tab = "first"

    var body: some View {
        Button("tab=\(tab)") { tab = "second" }
    }
}

private struct StorageApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { TabPage() }
        Window("Inspector", id: "inspector") { TabPage() }
        WindowGroup(id: "viewer") { TabPage() }
    }
}

// MARK: - Tests

@MainActor
@Suite("Scene storage per window", .serialized)
struct SceneStoragePerWindowTests {
    private var now: Int64 = 0

    private mutating func frame(_ app: HeadlessApp<StorageApp>) {
        now += 20_000_000
        app.frame(atNanos: now)
        now += 20_000_000
        app.frame(atNanos: now)
    }

    private mutating func launched() -> HeadlessApp<StorageApp> {
        StorageProbe.shared.store = MockStorageBackend()
        let app = HeadlessApp(StorageApp(), width: 40, height: 6)
        frame(app)
        return app
    }

    private func screen(_ app: HeadlessApp<StorageApp>) -> String {
        app.screen.map(\.stripped).joined(separator: "\n")
    }

    private func stored(_ key: String) -> String? {
        StorageProbe.shared.store.entry(forKey: key, as: String.self).value
    }

    /// Opens `id` and presses the new window's button.
    private mutating func openAndPress(_ id: String, in app: HeadlessApp<StorageApp>) {
        app.scenes.open(WindowTarget(id: id))
        frame(app)
        app.send(KeyEvent(key: .enter))
        frame(app)
    }

    @Test("The window opened at launch keeps its scene storage under scene., as an app of one window did")
    mutating func launchWindowNamespace() {
        let app = launched()
        app.send(KeyEvent(key: .enter))
        frame(app)
        #expect(stored("scene.tab") == "second")
    }

    @Test("Another window's scene storage is its own: written there, it leaves the launch window's alone")
    mutating func windowsKeepTheirOwn() {
        let app = launched()
        app.scenes.open(WindowTarget(id: "inspector"))
        frame(app)
        #expect(screen(app).contains("tab=first"))
        app.send(KeyEvent(key: .enter))
        frame(app)
        #expect(stored("scene.inspector.tab") == "second")
        #expect(stored("scene.tab") == nil)
        app.send(KeyEvent(key: .escape))
        frame(app)
        #expect(screen(app).contains("tab=first"), "the launch window's own: \(screen(app))")
    }

    @Test("A group's windows past the first are told apart by their ordinal")
    mutating func groupOrdinals() {
        let app = launched()
        openAndPress("viewer", in: app)
        openAndPress("viewer", in: app)
        #expect(stored("scene.viewer.tab") == "second")
        #expect(stored("scene.viewer#2.tab") == "second")
    }
}
