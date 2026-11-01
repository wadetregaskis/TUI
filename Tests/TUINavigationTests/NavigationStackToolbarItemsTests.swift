//  🖥️ TUI — A Terminal UI framework for Swift
//  NavigationStackToolbarItemsTests.swift
//
//  A screen pushed onto a navigation stack puts its top-bar items in the
//  stack's bar — leading after ‹ Back, the rest at the trailing end — while
//  its bottom-bar items stay the window's, and the root's top items are the
//  window's.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUINavigation
import TUITesting
@testable import TUITestSupport

/// The probe's path and what its items did, reachable from an `App`.
private final class StackProbe: @unchecked Sendable {
    static let shared = StackProbe()
    var path: [Int] = []
    var saved = 0
    var store = MockStorageBackend()
}

/// A stack whose root and pushed screen each declare items.
private struct StackItemsApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: Binding(get: { StackProbe.shared.path }, set: { StackProbe.shared.path = $0 })) {
                Text("ROOT")
                    .navigationTitle("Planets")
                    .toolbar { ToolbarItem(placement: .primaryAction) { Text("ROOTITEM") } }
                    .navigationDestination(for: Int.self) { number in
                        Text("SCREEN \(number)")
                            .navigationTitle("Earth")
                            .toolbar {
                                ToolbarItem(placement: .navigation) { Text("LEAD") }
                                ToolbarItem(placement: .primaryAction) {
                                    Button("SAVE") { StackProbe.shared.saved += 1 }
                                        .keyboardShortcut("s", modifiers: [])
                                }
                                ToolbarItem(placement: .bottomBar) { Text("BOTTOMITEM") }
                            }
                    }
            }
        }
        .windowToolbarStyle(.unifiedCompact)
    }
}

/// A pushed screen with a customizable toolbar: two items in the stack's bar,
/// and one in the window's bottom bar, whose context menu customizes it.
private struct StackCustomizableApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            NavigationStack(path: Binding(get: { StackProbe.shared.path }, set: { StackProbe.shared.path = $0 })) {
                Text("ROOT")
                    .navigationDestination(for: Int.self) { _ in
                        Text("SCREEN")
                            .navigationTitle("Earth")
                            .toolbar(id: "pushed") {
                                ToolbarItem(id: "one", placement: .primaryAction) { Text("ONE") }
                                ToolbarItem(id: "two", placement: .primaryAction) { Text("TWO") }
                                ToolbarItem(id: "low", placement: .bottomBar) { Text("LOW") }
                            }
                    }
            }
        }
        .defaultAppStorage(StackProbe.shared.store)
        .windowToolbarStyle(.unifiedCompact)
    }
}

@MainActor
@Suite("Navigation stack toolbar items", .serialized)
struct NavigationStackToolbarItemsTests {

    private func reset() {
        StackProbe.shared.path = []
        StackProbe.shared.saved = 0
        StackProbe.shared.store = MockStorageBackend()
    }

    /// The screen after a few frames: enough to declare, adopt and settle.
    private func frames(_ app: TestApp, from now: inout Int64) -> [String] {
        for _ in 0..<3 {
            now += 20_000_000
            app.frame(atNanos: now)
        }
        return app.screen.lines
    }

    @Test("A pushed screen's top items are in the stack's bar, its bottom items in the window's")
    func pushedScreenItems() {
        reset()
        defer { reset() }
        StackProbe.shared.path = [3]
        let app = TestApp(StackItemsApp(), width: 50, height: 10)
        var now: Int64 = 0
        let rows = frames(app, from: &now)
        // No window top bar: the root's item went with the root, and the
        // screen's top items are the stack's.
        // The trail (the room allows it), the leading item after it, and the
        // primary item at the trailing end.
        let bar = rows.first ?? ""
        #expect(bar.contains("Planets › Earth") && bar.contains("LEAD") && bar.hasSuffix("SAVE ▌"), "\(rows)")
        if let trail = bar.range(of: "Earth"), let lead = bar.range(of: "LEAD"), let save = bar.range(of: "SAVE") {
            #expect(trail.lowerBound < lead.lowerBound && lead.lowerBound < save.lowerBound, "\(bar)")
        }
        #expect(!rows.contains { $0.contains("ROOTITEM") }, "\(rows)")
        #expect(rows.last?.contains("BOTTOMITEM") == true, "the bottom bar stays the window's: \(rows)")
        #expect(rows.filter { $0.contains("SAVE") }.count == 1, "drawn once, in the stack's bar: \(rows)")

        // The item is live: its shortcut runs it.
        _ = app.send(KeyEvent(key: .character("s")))
        #expect(StackProbe.shared.saved == 1)
    }

    @Test("Launched with a screen pushed, the first frame seeds no window top bar for the screen's items")
    func firstFrameSeedsNoTopBar() {
        reset()
        defer { reset() }
        StackProbe.shared.path = [3]
        let app = TestApp(StackItemsApp(), width: 50, height: 10)
        app.frame(atNanos: 0)
        let first = app.screen.lines
        // The stack's bar is the first row from the first frame: no rows of
        // the window's top bar, reserved for items that went to the stack's
        // bar, drawn blank above it and taken away a frame later.
        #expect(first.first?.contains("SAVE") == true, "\(first)")
        var now: Int64 = 0
        let settled = frames(app, from: &now)
        #expect(first.firstIndex { $0.contains("SCREEN 3") } == settled.firstIndex { $0.contains("SCREEN 3") }, "\(first) \(settled)")
    }

    @Test("At the root, the root's top items are the window's")
    func rootItems() {
        reset()
        defer { reset() }
        let app = TestApp(StackItemsApp(), width: 50, height: 10)
        var now: Int64 = 0
        let rows = frames(app, from: &now)
        #expect(rows.first?.contains("ROOTITEM") == true, "\(rows)")
        #expect(!rows.contains { $0.contains("SAVE") }, "\(rows)")
    }

    /// Off the bar is judged against the rows of the bar the item is drawn
    /// in: the stack's, not the window's bottom bar's, as it was — so a click
    /// on the item took it out.
    @Test("While customizing, a pushed screen's item in the stack's bar stays on a click, and moves when dragged")
    func customizingInTheStackBar() {
        reset()
        defer { reset() }
        StackProbe.shared.path = [3]
        let app = TestApp(StackCustomizableApp(), width: 50, height: 12)
        var now: Int64 = 0
        var rows = frames(app, from: &now)
        func position(of text: String) -> (x: Int, y: Int)? {
            for (row, line) in rows.enumerated() {
                if let found = line.range(of: text) { return (line.distance(from: line.startIndex, to: found.lowerBound), row) }
            }
            return nil
        }
        func send(_ phase: MousePhase, _ point: (x: Int, y: Int), button: MouseButton = .left) {
            _ = app.send(MouseEvent(button: button, phase: phase, x: point.x, y: point.y))
            rows = frames(app, from: &now)
        }
        guard let low = position(of: "LOW") else {
            Issue.record("\(rows)")
            return
        }
        send(.pressed, low, button: .right)
        send(.released, low, button: .right)
        guard let customize = position(of: "Customize Toolbar") else {
            Issue.record("no context menu: \(rows)")
            return
        }
        send(.pressed, customize)
        send(.released, customize)
        #expect(rows.contains { $0.contains("Done") }, "the panel: \(rows)")
        guard let one = position(of: "ONE") else {
            Issue.record("\(rows)")
            return
        }
        // A click: nothing is taken out.
        send(.pressed, one)
        send(.released, one)
        #expect(rows[one.y].contains("ONE"), "\(rows)")
        // Dragged sideways past TWO, it goes after it.
        send(.pressed, one)
        for step in 1...4 { send(.dragged, (one.x + step, one.y)) }
        send(.released, (one.x + 4, one.y))
        let bar = rows[one.y]
        if let first = bar.range(of: "ONE"), let second = bar.range(of: "TWO") {
            #expect(second.lowerBound < first.lowerBound, "\(rows)")
        } else {
            Issue.record("\(rows)")
        }
    }
}
