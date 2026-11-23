//  🖥️ TUI — A Terminal UI framework for Swift
//  SceneStorageTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIFoundation
@testable import TUITestSupport

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

    /// A prefix in the same store was a namespace only by convention:
    /// `@AppStorage("scene.tab")` was the launch window's `@SceneStorage("tab")`
    /// under another name, so writing either changed the other (bug hunt,
    /// 2026-11-17). Scene state is in a store of its own now, which no key of
    /// the app's store can name — in a store of an app's own, and in the file
    /// store an app keeps its settings in.
    @Test("No @AppStorage key names a scene's value, the scene's prefixed key included")
    func noAppStorageKeyNamesSceneState() throws {
        func check(_ backend: any StorageBackend, _ name: String) {
            let scene = SceneStorage(wrappedValue: "inbox", "tab", store: backend)
            let prefixed = AppStorage(wrappedValue: "none", "scene.tab", store: backend)
            let plain = AppStorage(wrappedValue: "none", "tab", store: backend)
            scene.wrappedValue = "archive"
            #expect(prefixed.wrappedValue == "none", "\(name): the scene's write reached @AppStorage(\"scene.tab\")")
            #expect(plain.wrappedValue == "none", "\(name): the scene's write reached @AppStorage(\"tab\")")
            prefixed.wrappedValue = "chosen"
            plain.wrappedValue = "chosen"
            #expect(scene.wrappedValue == "archive", "\(name): an app storage write reached the scene's")
        }
        check(MockStorageBackend(), "a store of the app's own")
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tui.scene-state.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = JSONFileStorage(fileURL: directory.appendingPathComponent("settings.json"))
        check(file, "the settings file")
        file.synchronize()
    }

    @Test("The settings file's scene state is kept in a file beside it")
    func fileStoreKeepsSceneStateBeside() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tui.scene-state.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = JSONFileStorage(fileURL: directory.appendingPathComponent("settings.json"))
        SceneStorage(wrappedValue: "inbox", "tab", store: file).wrappedValue = "archive"
        file.sceneStateStore.synchronize()
        let beside = JSONFileStorage(fileURL: directory.appendingPathComponent("settings.scenes.json"))
        #expect(beside.value(forKey: "tab") == Optional("archive"))
        #expect(file.value(forKey: "tab") as String? == nil && file.value(forKey: "scene.tab") as String? == nil)
        // Asked twice: the same store each time, as the protocol requires.
        let asked = ObjectIdentifier(file.sceneStateStore as AnyObject)
        let askedAgain = ObjectIdentifier(file.sceneStateStore as AnyObject)
        #expect(asked == askedAgain, "one store, every time")
    }

    /// The scene state is saved on a queue of the scene store's own, which the
    /// app's store's flush did not wait for, and quitting flushed only that:
    /// a scene's write just before a quit could miss its file (bug hunt
    /// FENV-1, 2026-11-20).
    @Test("Flushing the settings file flushes its scene state, and makes no scene store to flush")
    func fileStoreFlushesItsSceneState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tui.scene-flush.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let scenes = directory.appendingPathComponent("settings.scenes.json")
        let untouched = JSONFileStorage(fileURL: directory.appendingPathComponent("untouched.json"))
        untouched.synchronize()
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("untouched.scenes.json").path))
        let file = JSONFileStorage(fileURL: directory.appendingPathComponent("settings.json"))
        let tab = SceneStorage(wrappedValue: "inbox", "tab", store: file)
        for name in ["archive", "drafts", "sent"] { tab.wrappedValue = name }
        file.synchronize()
        // Read straight from the file, as the next launch reads it.
        let bytes = try Data(contentsOf: scenes)
        let saved = try #require(try JSONSerialization.jsonObject(with: bytes) as? [String: String])
        #expect(saved["tab"].flatMap { Data(base64Encoded: $0) } == Data(#""sent""#.utf8))
        #expect(JSONFileStorage(fileURL: scenes).value(forKey: "tab") == Optional("sent"))
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
        #expect(backend.sceneStateMock.value(forKey: "pane") == Optional("detail"))
        backend.sceneStateMock.setValue("gallery", forKey: "pane")
        #expect(pane.wrappedValue == .list, "a raw value that is no case reads as nothing stored")
    }
}
