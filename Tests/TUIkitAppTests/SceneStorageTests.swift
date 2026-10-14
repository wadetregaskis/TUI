//  🖥️ TUIkit — Terminal UI Kit for Swift
//  SceneStorageTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIkit
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

/// `@SceneStorage` — SwiftUI's per-scene state restoration, in an app that has
/// exactly one scene.
///
/// The one behaviour that survives having a single scene is the **namespace**,
/// so that is what these pin: scene state and app preferences must not collide
/// on a shared key, or an app that stores `"tab"` in both loses one of them.
@MainActor
@Suite("SceneStorage")
struct SceneStorageTests {

    @Test("It stores and reads back")
    func roundTrips() {
        let backend = MockStorageBackend()
        let tab = SceneStorage(wrappedValue: "inbox", "selectedTab", store: backend)
        #expect(tab.wrappedValue == "inbox")

        tab.wrappedValue = "archive"
        #expect(tab.wrappedValue == "archive")

        // A second wrapper over the same key and backend sees it — which is
        // what makes it storage rather than @State.
        let other = SceneStorage(wrappedValue: "inbox", "selectedTab", store: backend)
        #expect(other.wrappedValue == "archive")
    }

    @Test("Scene state and app preferences do not collide")
    func namespacesAreSeparate() {
        // The whole reason this wrapper exists rather than being an alias:
        // "where the user was" and "what the user chose" are different
        // questions, and an app is entitled to use the same word for both.
        let backend = MockStorageBackend()
        let scene = SceneStorage(wrappedValue: 0, "position", store: backend)
        let app = AppStorage(wrappedValue: 0, "position", store: backend)

        scene.wrappedValue = 42
        #expect(scene.wrappedValue == 42)
        #expect(app.wrappedValue == 0)

        app.wrappedValue = 7
        #expect(scene.wrappedValue == 42)
        #expect(app.wrappedValue == 7)
    }

    @Test("The optional forms start nil and store a value")
    func optionalForms() {
        let backend = MockStorageBackend()
        let name = AppStorage<String?>("nickname", store: backend)
        #expect(name.wrappedValue == nil)
        name.wrappedValue = "Ada"
        #expect(AppStorage<String?>("nickname", store: backend).wrappedValue == "Ada")
        name.wrappedValue = nil
        #expect(name.wrappedValue == nil)
        // SceneStorage's optional form takes the default store, as SwiftUI's
        // does; a key nothing has written reads as nil. Read only, so the
        // test process's real defaults are never written.
        #expect(SceneStorage<Int?>("never-written-\(UUID().uuidString)").wrappedValue == nil)
    }

    @Test("The binding writes through")
    func bindingWritesThrough() {
        let backend = MockStorageBackend()
        let tab = SceneStorage(wrappedValue: "inbox", "tab", store: backend)
        let binding = tab.projectedValue
        binding.wrappedValue = "sent"
        #expect(tab.wrappedValue == "sent")
    }

    @Test("It carries whatever Codable value it was given")
    func codableValues() {
        struct Position: Codable, Equatable {
            var row: Int
            var column: Int
        }
        let backend = MockStorageBackend()
        let cursor = SceneStorage(
            wrappedValue: Position(row: 0, column: 0), "cursor", store: backend)
        cursor.wrappedValue = Position(row: 3, column: 9)
        #expect(cursor.wrappedValue == Position(row: 3, column: 9))

        let bools = SceneStorage(wrappedValue: false, "expanded", store: backend)
        bools.wrappedValue = true
        #expect(bools.wrappedValue)
    }

    @Test("A view can hold one")
    func usableInAView() {
        struct TabView2: View {
            @SceneStorage("sceneTestTab") private var tab = "one"
            var body: some View { Text(tab) }
        }
        let rendered = renderToBuffer(TabView2(), context: makeRenderContext(width: 20, height: 2))
        #expect(rendered.lines[0].stripped.contains("one"))
    }
}

// MARK: - Raw-representable values

/// A `String`-backed enum that is not `Codable`, as SwiftUI's scene storage
/// takes it (the semantic audit's item 85).
private enum Pane: String {
    case list, detail
}

@Suite("SceneStorage of raw-representable values")
struct SceneStorageRawValueTests {
    @Test("A raw-representable that is not Codable is stored as its raw value, within the scene's namespace")
    func storedAsRawValue() {
        let backend = MockStorageBackend()
        let pane = SceneStorage(wrappedValue: Pane.list, "pane", store: backend)
        #expect(pane.wrappedValue == .list)
        pane.wrappedValue = .detail
        #expect(pane.wrappedValue == .detail)
        #expect(backend.value(forKey: "scene.pane") == Optional("detail"))
        backend.setValue("gallery", forKey: "scene.pane")
        #expect(pane.wrappedValue == .list, "a raw value that is no case reads as nothing stored")
    }
}
