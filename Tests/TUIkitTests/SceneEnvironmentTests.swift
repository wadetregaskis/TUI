//  🖥️ TUIkit — Terminal UI Kit for Swift
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

@testable import TUIkit

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
            GreetingLabel().appHeader { GreetingLabel() }
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
        let headless = HeadlessApp(app, width: 30, height: 12)
        headless.frame(atNanos: 0)
        return headless.screen.map(\.stripped)
    }

    @Test("An observable object reaches the content and the app header, through .palette")
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
