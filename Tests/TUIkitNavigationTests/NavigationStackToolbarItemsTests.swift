//  🖥️ TUIkit — Terminal UI Kit for Swift
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

@testable import TUIkitApp
@testable import TUIkitAppTestSupport
@testable import TUIkitCore
@testable import TUIkitFoundation
import TUIkitNavigation
@testable import TUIkitTestSupport

/// The probe's path and what its items did, reachable from an `App`.
private final class StackProbe: @unchecked Sendable {
    static let shared = StackProbe()
    var path: [Int] = []
    var saved = 0
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

@MainActor
@Suite("Navigation stack toolbar items", .serialized)
struct NavigationStackToolbarItemsTests {

    private func reset() {
        StackProbe.shared.path = []
        StackProbe.shared.saved = 0
    }

    /// The screen after a few frames: enough to declare, adopt and settle.
    private func frames(_ app: HeadlessApp<StackItemsApp>, from now: inout Int64) -> [String] {
        for _ in 0..<3 {
            now += 20_000_000
            app.frame(atNanos: now)
        }
        return app.screen.map(\.stripped)
    }

    @Test("A pushed screen's top items are in the stack's bar, its bottom items in the window's")
    func pushedScreenItems() {
        reset()
        defer { reset() }
        StackProbe.shared.path = [3]
        let app = HeadlessApp(StackItemsApp(), width: 50, height: 10)
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
        let app = HeadlessApp(StackItemsApp(), width: 50, height: 10)
        app.frame(atNanos: 0)
        let first = app.screen.map(\.stripped)
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
        let app = HeadlessApp(StackItemsApp(), width: 50, height: 10)
        var now: Int64 = 0
        let rows = frames(app, from: &now)
        #expect(rows.first?.contains("ROOTITEM") == true, "\(rows)")
        #expect(!rows.contains { $0.contains("SAVE") }, "\(rows)")
    }
}
