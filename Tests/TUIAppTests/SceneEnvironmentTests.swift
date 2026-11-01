//  🖥️ TUI — A Terminal UI framework for Swift
//  SceneEnvironmentTests.swift
//
//  `.environment(_:_:)`, `.environment(_:)` and `.transformEnvironment` written
//  on a scene: the values reach the content and the app header drawn outside
//  it, the innermost wins, and they pass through the other scene modifiers.
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUITesting
@testable import TUITestSupport

@Observable
private final class Greeting {
    var word: String
    init(_ word: String) { self.word = word }
}

private struct GreetingLabel: View {
    @Environment(Greeting.self) private var greeting
    var body: some View { Text("say \(greeting.word)") }
}

private struct CountKey: EnvironmentKey {
    static let defaultValue = 0
}

extension EnvironmentValues {
    fileprivate var sceneCount: Int {
        get { self[CountKey.self] }
        set { self[CountKey.self] = newValue }
    }
}

private struct CountLabel: View {
    @Environment(\.sceneCount) private var count
    var body: some View { Text("count \(count)") }
}

private struct ObjectApp: App {
    let greeting = Greeting("hello")
    var body: some Scene {
        WindowGroup {
            GreetingLabel().toolbar { ToolbarItem(placement: .navigation) { GreetingLabel() } }
        }
        .palette(SystemPalette.green)
        .environment(greeting)
    }
}

private struct ValueApp: App {
    var body: some Scene {
        WindowGroup { CountLabel() }
            .environment(\.sceneCount, 3)
            .environment(\.sceneCount, 7)
    }
}

private struct TransformApp: App {
    var body: some Scene {
        WindowGroup { CountLabel() }
            .transformEnvironment(\.sceneCount) { $0 += 1 }
            .environment(\.sceneCount, 4)
    }
}

@MainActor
@Suite("Scene-level environment")
struct SceneEnvironmentTests {

    private func screen(_ app: some App) -> [String] {
        let headless = TestApp(app, width: 30, height: 12)
        headless.frame(atNanos: 0)
        return headless.screen.lines
    }

    @Test("An observable object reaches the content and a toolbar item, through .palette")
    func objectReachesContentAndHeader() {
        let lines = screen(ObjectApp())
        #expect(lines.filter { $0.contains("say hello") }.count == 2, "\(lines)")
    }

    @Test("A value reaches the content, and the scene closest to it wins")
    func innermostValueWins() {
        let lines = screen(ValueApp())
        #expect(lines.contains { $0.contains("count 3") }, "\(lines)")
    }

    @Test("A transform sees the value an outer scene set")
    func transformSeesTheOuterValue() {
        let lines = screen(TransformApp())
        #expect(lines.contains { $0.contains("count 5") }, "\(lines)")
    }
}

// MARK: - onChange

private final class ChangeLog: @unchecked Sendable {
    var entries: [String] = []
}

private let sceneChanges = ChangeLog()

private struct ChangingApp: App {
    var body: some Scene {
        WindowGroup { CountLabel() }
            .onChange(of: SceneChangeSource.value, initial: true) { old, new in
                sceneChanges.entries.append("\(old)→\(new)")
            }
            .palette(SystemPalette.green)
    }
}

@MainActor
private enum SceneChangeSource {
    static var value = 1
}

@MainActor
@Suite("Scene-level onChange")
struct SceneOnChangeTests {
    @Test("A scene's onChange runs initially, and again when its value changes between frames")
    func runsOnChange() {
        sceneChanges.entries = []
        SceneChangeSource.value = 1
        let app = TestApp(ChangingApp(), width: 30, height: 12)
        app.frame(atNanos: 0)
        #expect(sceneChanges.entries == ["1→1"])
        app.frame(atNanos: 16_666_667)
        #expect(sceneChanges.entries == ["1→1"], "an unchanged value runs nothing")
        SceneChangeSource.value = 2
        app.frame(atNanos: 33_333_334)
        #expect(sceneChanges.entries == ["1→1", "1→2"])
        #expect(app.screen.contains("count 0"), "and the content still draws")
    }
}
