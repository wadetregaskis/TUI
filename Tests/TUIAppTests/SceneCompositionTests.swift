//  🖥️ TUI — A Terminal UI framework for Swift
//  SceneCompositionTests.swift
//
//  Several scenes in one body: SwiftUI's variadic `buildBlock`, `if #available`
//  around a scene (`buildOptional` / `buildLimitedAvailability`) and `Group`
//  of scenes. The first window scene is the one drawn at launch, its own
//  modifiers configure the frame, and a modifier on several scenes reaches
//  each of them.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIFoundation

// MARK: - Fixtures

/// Two window groups: the first opens at launch.
private struct TwoGroupsApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Text("first-group") }
        WindowGroup { Text("second-group") }
    }
}

/// The launch scene behind an availability check every supported system
/// passes, with another after it.
private struct AvailableSceneApp: App {
    init() {}
    var body: some Scene {
        if #available(macOS 14, *) {
            WindowGroup { Text("available-group") }
        }
        WindowGroup { Text("after-the-check") }
    }
}

/// A value the scene's environment carries.
private struct SceneLabelKey: EnvironmentKey {
    static let defaultValue = "unset"
}

extension EnvironmentValues {
    fileprivate var sceneLabel: String {
        get { self[SceneLabelKey.self] }
        set { self[SceneLabelKey.self] = newValue }
    }
}

/// Draws the scene's label.
private struct LabelReader: View {
    @Environment(\.sceneLabel) private var label
    var body: some View { Text("label=\(label)") }
}

/// A modifier written on a group of scenes reaches the one drawn.
private struct GroupModifierApp: App {
    init() {}
    var body: some Scene {
        Group {
            WindowGroup { LabelReader() }
            WindowGroup { Text("never-drawn") }
        }
        .environment(\.sceneLabel, "from-the-group")
    }
}

/// The second group's own modifier is not the first's.
private struct OwnModifierApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { LabelReader() }
        WindowGroup { LabelReader() }
            .environment(\.sceneLabel, "second-only")
    }
}

/// A counter whose state must survive frames at the first scene's identity.
private struct Counter: View {
    @State private var count = 0
    var body: some View {
        Button("count=\(count)") { count += 1 }
    }
}

private struct StatefulTwoGroupsApp: App {
    init() {}
    var body: some Scene {
        WindowGroup { Counter() }
        WindowGroup { Text("second") }
    }
}

// MARK: - Tests

@MainActor
@Suite("Several scenes in one body")
struct SceneCompositionTests {
    /// The app after its first frame.
    private func launched<A: App>(_ app: A) -> HeadlessApp {
        let headless = HeadlessApp(app, width: 40, height: 6)
        headless.frame(atNanos: 0)
        return headless
    }

    private func screen(_ app: HeadlessApp) -> String {
        app.screen.map(\.stripped).joined(separator: "\n")
    }

    @Test("Of two window groups, the first is the one drawn at launch")
    func firstGroupDrawn() {
        let text = screen(launched(TwoGroupsApp()))
        #expect(text.contains("first-group"))
        #expect(!text.contains("second-group"))
    }

    @Test("A scene inside if #available is built and drawn")
    func availabilityChecked() {
        let text = screen(launched(AvailableSceneApp()))
        #expect(text.contains("available-group"))
        #expect(!text.contains("after-the-check"))
    }

    @Test("A modifier on a Group of scenes reaches the scene drawn")
    func groupModifierReachesScene() {
        #expect(screen(launched(GroupModifierApp())).contains("label=from-the-group"))
    }

    @Test("A modifier on one scene of a block configures that scene alone")
    func siblingModifierStaysWithItsScene() {
        let text = screen(launched(OwnModifierApp()))
        #expect(text.contains("label=unset"))
        #expect(!text.contains("second-only"))
    }

    @Test("The launch scene's state lives from frame to frame inside a block")
    func stateSurvivesInsideBlock() {
        let app = launched(StatefulTwoGroupsApp())
        app.send(KeyEvent(key: .enter))
        app.frame(atNanos: 20_000_000)
        app.send(KeyEvent(key: .enter))
        app.frame(atNanos: 40_000_000)
        #expect(screen(app).contains("count=2"))
    }

    @Test("The catalogue lists every window scene in declaration order, each at its own identity")
    func catalogueOrderAndIdentities() {
        let root = ViewIdentity(rootType: TwoGroupsApp.self)
        let catalog = SceneCatalog(TwoGroupsApp().body, identity: root)
        #expect(catalog.windows.map(\.path) == [[0], [1]])
        #expect(catalog.windows[0].identity != catalog.windows[1].identity)
        #expect(catalog.launchTarget == SceneRenderTarget(path: [0]))
    }

    @Test("A bare window group is the launch scene at the scene's own identity, with no path")
    func bareGroupKeepsItsIdentity() {
        let root = ViewIdentity(rootType: Never.self)
        let catalog = SceneCatalog(WindowGroup { Text("x") }, identity: root)
        #expect(catalog.windows.count == 1)
        #expect(catalog.windows[0].path.isEmpty)
        #expect(catalog.windows[0].identity == root)
    }
}
