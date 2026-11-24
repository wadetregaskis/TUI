//  🖥️ TUI — A Terminal UI framework for Swift
//  UserDefaultsDirectWriteTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
import Foundation
import Testing

@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUITesting
@testable import TUIView

/// An `@AppStorage` over a `UserDefaults` is redrawn by a write made to the
/// `UserDefaults` itself, not through TUI: a settings model that writes
/// `UserDefaults.standard` while its views read `@AppStorage`, an ordinary
/// SwiftUI shape. Only TUI's own writes redrew it before (bug hunt FENV-4,
/// 2026-11-20).
@MainActor
@Suite("A write made to UserDefaults directly redraws the @AppStorage that reads it")
struct UserDefaultsDirectWriteTests {

    /// Reads `key` through `@AppStorage(_:store:)`, a store made afresh with
    /// every body, as SwiftUI's form makes it.
    private struct Reader: View {
        let defaults: UserDefaults
        let key: String
        var body: some View {
            let value = AppStorage(wrappedValue: "unset", key, store: defaults)
            return Text("value \(value.wrappedValue)")
        }
    }

    /// The spelling SwiftUI code commonly uses: a `UserDefaults` made afresh
    /// with every view value, which nothing holds once the body has run.
    private struct InlineReader: View {
        @AppStorage private var value: String

        init(suite: String, key: String) {
            _value = AppStorage(wrappedValue: "unset", key, store: UserDefaults(suiteName: suite))
        }

        var body: some View {
            Text("value \(value)")
        }
    }

    /// A suite of its own in a folder of its own, removed afterwards with
    /// everything the preferences daemon wrote (see `UserDefaultsStorageTests`).
    private static func withSuite(_ body: (String) async throws -> Void) async rethrows {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tuikit.tests.\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let suite = directory.appendingPathComponent("defaults").path
        defer {
            UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        try await body(suite)
    }

    private static func draw(_ app: TestApp, _ frame: inout Int64) -> String {
        frame += 100_000_000
        app.frame(atNanos: frame)
        return app.screen.lines.joined(separator: "\n")
    }

    @Test("A write through another UserDefaults of the suite asks for a frame, which shows it")
    func suiteWrite() async {
        await Self.withSuite { suite in
            let key = "direct-\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            let app = TestApp(width: 30, height: 3) { Reader(defaults: defaults, key: key) }
            var frame: Int64 = 1_000_000_000
            #expect(Self.draw(app, &frame).contains("value unset"))
            _ = app.takeFrameRequest()

            UserDefaults(suiteName: suite)!.set("direct", forKey: key)
            #expect(app.takeFrameRequest(), "the write asked for no frame")
            #expect(Self.draw(app, &frame).contains("value direct"), "the view kept the old value")

            UserDefaults(suiteName: suite)!.removeObject(forKey: key)
            #expect(app.takeFrameRequest(), "the removal asked for no frame")
            #expect(Self.draw(app, &frame).contains("value unset"))
        }
    }

    @Test("A view whose UserDefaults is made afresh with it is redrawn by a direct write")
    func inlineSuiteWrite() async {
        await Self.withSuite { suite in
            let key = "inline-\(UUID().uuidString)"
            let app = TestApp(width: 30, height: 3) { InlineReader(suite: suite, key: key) }
            var frame: Int64 = 1_000_000_000
            #expect(Self.draw(app, &frame).contains("value unset"))
            _ = app.takeFrameRequest()

            UserDefaults(suiteName: suite)!.set("direct", forKey: key)
            #expect(app.takeFrameRequest(), "the write asked for no frame")
            #expect(Self.draw(app, &frame).contains("value direct"), "the view kept the old value")
        }
    }

    /// `KVO` would read `editor.font` as a path, and end the app when `editor`
    /// is written: the watcher takes any key.
    @Test("A key with a dot in it is watched, and a write to its first part ends nothing")
    func dottedKey() async {
        await Self.withSuite { suite in
            let key = "editor-\(UUID().uuidString).font"
            let defaults = UserDefaults(suiteName: suite)!
            let app = TestApp(width: 60, height: 3) { Reader(defaults: defaults, key: key) }
            var frame: Int64 = 1_000_000_000
            _ = Self.draw(app, &frame)
            _ = app.takeFrameRequest()

            let head = String(key.prefix { $0 != "." })
            UserDefaults(suiteName: suite)!.set("not a dictionary", forKey: head)
            UserDefaults(suiteName: suite)!.set("Menlo", forKey: key)
            #expect(app.takeFrameRequest(), "the write asked for no frame")
            #expect(Self.draw(app, &frame).contains("value Menlo"))
        }
    }

    /// Off the main thread the change reaches the view on the main actor's
    /// next turn, as another process's would.
    @Test("A write made off the main thread is drawn")
    func backgroundWrite() async throws {
        try await Self.withSuite { suite in
            let key = "background-\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            let app = TestApp(width: 30, height: 3) { Reader(defaults: defaults, key: key) }
            #expect(app.screen.contains("value unset"))

            await Task.detached { UserDefaults(suiteName: suite)!.set("background", forKey: key) }.value
            try await app.wait(for: "value background", timeout: .seconds(10))
        }
    }

    #if os(macOS)
    /// Another process's write, which KVO hears with no run loop running, as
    /// TUI's async `main` runs none.
    @Test("Another process's defaults write is drawn")
    func otherProcessWrite() async throws {
        try await Self.withSuite { suite in
            let key = "process-\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            let app = TestApp(width: 60, height: 3) { Reader(defaults: defaults, key: key) }
            #expect(app.screen.contains("value unset"))

            let writer = Process()
            writer.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
            writer.arguments = ["write", suite, key, "-string", "elsewhere"]
            // Its end awaited, not `waitUntilExit()`, which runs the run loop
            // a terminal app does not.
            try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, any Error>) in
                writer.terminationHandler = { _ in done.resume() }
                do { try writer.run() } catch { done.resume(throwing: error) }
            }
            try await app.wait(for: "value elsewhere", timeout: .seconds(10))
        }
    }
    #endif

    /// `.standard`, the app's own domain: a key nothing else can name, removed
    /// afterwards, so the user's preferences are left as they were.
    @Test("A write to UserDefaults.standard redraws an @AppStorage of .standard")
    func standardWrite() {
        let key = "tuikitTestsDirect-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let app = TestApp(width: 60, height: 3) { Reader(defaults: .standard, key: key) }
        var frame: Int64 = 1_000_000_000
        #expect(Self.draw(app, &frame).contains("value unset"))
        _ = app.takeFrameRequest()

        UserDefaults.standard.set("standard", forKey: key)
        #expect(app.takeFrameRequest(), "the write asked for no frame")
        #expect(Self.draw(app, &frame).contains("value standard"))
    }

    /// A key with a dot is compared at every write in the process, and other
    /// tests write `.standard` on other threads at once: whichever compares
    /// first announces it, so the frame may be asked for on the main actor's
    /// next turn rather than at once. `wait(for:)` draws only frames the app
    /// asks for.
    @Test("A write to a dotted key of UserDefaults.standard is drawn")
    func standardDottedWrite() async throws {
        let key = "tuikit.tests.direct-\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let app = TestApp(width: 60, height: 3) { Reader(defaults: .standard, key: key) }
        #expect(app.screen.contains("value unset"))

        UserDefaults.standard.set("dotted", forKey: key)
        try await app.wait(for: "value dotted", timeout: .seconds(10))
    }

    /// A write to a key the views did not read redraws nothing.
    @Test("A write to a key nobody read asks for no frame")
    func otherKeyWrite() async {
        await Self.withSuite { suite in
            let key = "read-\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            let app = TestApp(width: 30, height: 3) { Reader(defaults: defaults, key: key) }
            var frame: Int64 = 1_000_000_000
            _ = Self.draw(app, &frame)
            _ = app.takeFrameRequest()

            UserDefaults(suiteName: suite)!.set("elsewhere", forKey: "unread-\(UUID().uuidString)")
            #expect(!app.takeFrameRequest(), "a write to another key asked for a frame")
        }
    }
}
#endif
