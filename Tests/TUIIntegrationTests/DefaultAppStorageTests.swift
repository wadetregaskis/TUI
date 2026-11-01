//  🖥️ TUI — A Terminal UI framework for Swift
//  DefaultAppStorageTests.swift
//
//  `defaultAppStorage(_:)` and the `store:` forms that take a `UserDefaults`
//  (decisions A18): an `@AppStorage` that names no store reads and writes the
//  one set nearest above its view, found before its body runs; one that names
//  a store keeps it; and a write through any store over a defaults domain
//  redraws the views that read the key through another.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Observation
import Testing

import TUI
@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport
@testable import TUIView

/// Which of two default stores ``DefaultAppStorageTests/Switching`` sets.
/// File-level: `@Observable`'s expansion cannot name a private nested type.
@Observable
private final class Choice: @unchecked Sendable {
    var second = false
}

@MainActor
@Suite("defaultAppStorage and the UserDefaults store forms")
struct DefaultAppStorageTests {

    /// Equal to every other: a memo serves it unless something it read, or
    /// the environment above it, changed.
    private struct Kept<Content: View>: View, @preconcurrency Equatable {
        let content: Content
        var body: some View { content }
        static func == (lhs: Self, rhs: Self) -> Bool { true }
    }

    /// Shows the stored value of `defaultAppStorage.value`, from whichever
    /// store its view's environment names.
    private struct Reader: View {
        let label: String
        @AppStorage("defaultAppStorage.value") var value = "none"
        var body: some View { Text("\(label) \(value)") }
    }

    /// Names a store of its own for the same key.
    private struct NamedReader: View {
        @AppStorage var value: String
        init(store: any StorageBackend) {
            _value = AppStorage(wrappedValue: "none", "defaultAppStorage.value", store: store)
        }
        var body: some View { Text("named \(value)") }
    }

    /// Hands out the binding its body made, as a control's action would hold
    /// it.
    private final class Captured: @unchecked Sendable {
        var binding: Binding<String>?
    }

    /// Its key is new each run: were the write to miss the view's store, it
    /// would land in the process's default one, which a test run keeps on
    /// disk, and a fixed key would fail every later run too.
    private struct BindingReader: View {
        let captured: Captured
        @AppStorage var value: String
        init(captured: Captured, key: String) {
            self.captured = captured
            _value = AppStorage(wrappedValue: "none", key)
        }
        var body: some View {
            captured.binding = $value
            return Text("captured \(value)")
        }
    }

    /// Hosts a page for ``TestApp``.
    private struct Page<Content: View>: App {
        let make: @MainActor () -> Content
        /// `App`'s requirement; these apps are built with ``init(content:)``.
        init() { self.make = { fatalError("built with init(content:)") } }
        init(content: Content) { self.make = { content } }
        var body: some Scene { WindowGroup { make() } }
    }

    private static func draw(_ app: TestApp, _ frame: inout Int64) -> String {
        for _ in 0..<2 {
            frame += 100_000_000
            app.frame(atNanos: frame)
        }
        return app.screen.styledLines.joined(separator: "\n").stripped
    }

    private static func store(holding value: String, forKey key: String = "defaultAppStorage.value")
        -> MockStorageBackend
    {
        let store = MockStorageBackend()
        store.setValue(value, forKey: key)
        return store
    }

    // MARK: - Which store

    @Test("A property that names no store reads the one set nearest above its view")
    func nearestStoreWins() {
        let (outer, inner) = (Self.store(holding: "outer"), Self.store(holding: "inner"))
        let page = VStack(alignment: .leading) {
            Reader(label: "a")
            Reader(label: "b").defaultAppStorage(inner)
        }
        .defaultAppStorage(outer)
        let app = TestApp(Page(content: page), width: 30, height: 6)
        var frame: Int64 = 1_000_000_000
        let screen = Self.draw(app, &frame)
        #expect(screen.contains("a outer"), "\(screen)")
        #expect(screen.contains("b inner"), "the nearer store did not win:\n\(screen)")
    }

    @Test("A property that names a store keeps it under a default store")
    func namedStoreWins() {
        let (environment, named) = (Self.store(holding: "environment"), Self.store(holding: "own"))
        let page = NamedReader(store: named).defaultAppStorage(environment)
        let app = TestApp(Page(content: page), width: 30, height: 4)
        var frame: Int64 = 1_000_000_000
        let screen = Self.draw(app, &frame)
        #expect(screen.contains("named own"), "\(screen)")
    }

    @Test("A scene's default store reaches its views, and a view's outweighs it")
    func sceneStore() {
        struct ScenePage: App {
            let scene: MockStorageBackend
            let view: MockStorageBackend
            init() { self.init(scene: MockStorageBackend(), view: MockStorageBackend()) }
            init(scene: MockStorageBackend, view: MockStorageBackend) { (self.scene, self.view) = (scene, view) }
            var body: some Scene {
                WindowGroup {
                    VStack(alignment: .leading) {
                        Reader(label: "a")
                        Reader(label: "b").defaultAppStorage(view)
                    }
                }
                .defaultAppStorage(scene)
            }
        }
        let app = TestApp(
            ScenePage(scene: Self.store(holding: "scene"), view: Self.store(holding: "view")), width: 30, height: 6)
        var frame: Int64 = 1_000_000_000
        let screen = Self.draw(app, &frame)
        #expect(screen.contains("a scene"), "\(screen)")
        #expect(screen.contains("b view"), "\(screen)")
    }

    // MARK: - Writes

    /// A binding the body made outlives the walk that found the store: it is
    /// how a control's action writes, after the frame.
    @Test("A binding the body made writes to the store found for its view, and the view redraws")
    func capturedBindingWritesThere() throws {
        let (store, captured) = (MockStorageBackend(), Captured())
        let key = "defaultAppStorage.captured.\(UUID().uuidString)"
        let page = Kept(content: BindingReader(captured: captured, key: key)).equatable().defaultAppStorage(store)
        let app = TestApp(Page(content: page), width: 30, height: 4)
        var frame: Int64 = 1_000_000_000
        #expect(Self.draw(app, &frame).contains("captured none"))

        let binding = try #require(captured.binding)
        binding.wrappedValue = "set"
        #expect(store.value(forKey: key) == Optional("set"), "not written to the view's store")
        let fallback: String? = StorageDefaults.backend.value(forKey: key)
        #expect(fallback == nil, "written to the process's default store")
        let screen = Self.draw(app, &frame)
        #expect(screen.contains("captured set"), "the reader was not redrawn:\n\(screen)")
    }

    /// Picks the default store by `choice`, above a reader a memo would serve.
    private struct Switching: View {
        let choice: Choice
        let first: MockStorageBackend
        let second: MockStorageBackend
        var body: some View {
            Kept(content: Reader(label: "kept")).equatable().defaultAppStorage(choice.second ? second : first)
        }
    }

    /// The default store is part of the environment a memo is kept under, so a
    /// reader the memo would serve is drawn again from the new store. (Today
    /// the change re-renders `Switching`, which drops the memo beneath it on
    /// its own; this pins the outcome whichever way it is reached.)
    @Test("Another default store redraws a reader a memo would otherwise serve")
    func changedStoreRedraws() {
        let choice = Choice()
        let page = Switching(
            choice: choice, first: Self.store(holding: "first"), second: Self.store(holding: "second"))
        let app = TestApp(Page(content: page), width: 30, height: 4)
        var frame: Int64 = 1_000_000_000
        #expect(Self.draw(app, &frame).contains("kept first"))
        choice.second = true
        let screen = Self.draw(app, &frame)
        #expect(screen.contains("kept second"), "the memo served the old store's value:\n\(screen)")
    }

    // MARK: - Equality

    private struct ValueStore: StorageBackend {
        func entry<T: Codable>(forKey key: String, as type: T.Type) -> (value: T?, key: StoredKey) { (nil, StoredKey()) }
        func store<T: Codable>(_ value: T, forKey key: String) -> StoredKey { StoredKey() }
        func remove(forKey key: String) -> StoredKey? { nil }
        func synchronize() {}
    }

    @Test("Default stores are equal when they read and write through one object, and a value store never is")
    func equality() {
        let (one, other) = (MockStorageBackend(), MockStorageBackend())
        let (first, again) = (DefaultAppStorage(one), DefaultAppStorage(one))
        #expect(first == again)
        #expect(first != DefaultAppStorage(other))
        let (value, otherValue) = (DefaultAppStorage(ValueStore()), DefaultAppStorage(ValueStore()))
        #expect(value != otherValue)
        #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
            // Each makes a new store over the object; they are equal by it.
            let (standard, standardAgain) = (DefaultAppStorage(UserDefaults.standard), DefaultAppStorage(.standard))
            #expect(standard == standardAgain)
        #endif
    }

    // MARK: - UserDefaults

    #if canImport(Darwin)
        /// A suite of its own, named by an absolute path so its file lives in a
        /// temporary directory (see `UserDefaultsStorageTests.withSuite`), with
        /// `value` stored for `key`; removed afterwards.
        private static func withSuite(
            holding value: String, forKey key: String, _ body: (String) throws -> Void
        ) rethrows {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("tuikit.tests.\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let suite = directory.appendingPathComponent("defaults").path
            UserDefaultsStorage(suiteName: suite).setValue(value, forKey: key)
            defer {
                UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
                try? FileManager.default.removeItem(at: directory)
            }
            try body(suite)
        }

        /// Reads through a `UserDefaults` made afresh each time the view is,
        /// as `store: UserDefaults(suiteName: …)` written in a view does.
        private struct SuiteReader: View {
            @AppStorage var value: String
            init(suite: String) {
                _value = AppStorage(wrappedValue: "none", "defaultAppStorage.suite", store: UserDefaults(suiteName: suite))
            }
            var body: some View { Text("suite \(value)") }
        }

        @Test("A write through another UserDefaults over the suite redraws a reader a memo would serve")
        func writeThroughAnotherDefaultsObject() throws {
            try Self.withSuite(holding: "one", forKey: "defaultAppStorage.suite") { suite in
                let page = Kept(content: SuiteReader(suite: suite)).equatable()
                let app = TestApp(Page(content: page), width: 30, height: 4)
                var frame: Int64 = 1_000_000_000
                #expect(Self.draw(app, &frame).contains("suite one"))

                AppStorage(wrappedValue: "", "defaultAppStorage.suite", store: UserDefaults(suiteName: suite))
                    .wrappedValue = "two"
                let written = Self.draw(app, &frame)
                #expect(written.contains("suite two"), "the reader kept the old value:\n\(written)")

                let another = try #require(UserDefaults(suiteName: suite))
                UserDefaultsStorage(another).removeValue(forKey: "defaultAppStorage.suite")
                let removed = Self.draw(app, &frame)
                #expect(removed.contains("suite none"), "the reader kept the removed value:\n\(removed)")
            }
        }

        @Test("defaultAppStorage(_:) with a UserDefaults reads that suite")
        func defaultsAsDefaultStore() throws {
            try Self.withSuite(holding: "from suite", forKey: "defaultAppStorage.value") { suite in
                let defaults = try #require(UserDefaults(suiteName: suite))
                let page = Reader(label: "env").defaultAppStorage(defaults)
                let app = TestApp(Page(content: page), width: 30, height: 4)
                var frame: Int64 = 1_000_000_000
                let screen = Self.draw(app, &frame)
                #expect(screen.contains("env from suite"), "\(screen)")
            }
        }

        private struct Row: Identifiable {
            let id: Int
        }

        /// SwiftUI's spellings, which must resolve without ambiguity beside
        /// TUI's `StorageBackend` forms. Compiled, never drawn.
        private struct Spellings: View {
            @AppStorage("spellings.optional") var optional: Int?
            @AppStorage("spellings.nil", store: nil) var explicitNil: String?
            @AppStorage("spellings.standard", store: .standard) var standard = 1
            @AppStorage("spellings.tabs", store: nil) var tabs: TabViewCustomization
            @AppStorage("spellings.columns") var columns: TableColumnCustomization<Row>
            @SceneStorage("spellings.scene-tabs", store: nil) var sceneTabs: TabViewCustomization
            var body: some View { EmptyView() }
        }

        @Test("SwiftUI's UserDefaults spellings compile beside TUI's own")
        func spellingsCompile() {
            _ = Spellings()
        }
    #endif
}
