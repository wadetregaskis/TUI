//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ToolbarReachTests.swift
//
//  What a toolbar item can be reached by, and when: an item drawn inert —
//  under a modal, or declared by a backdrop — keeps no click, key or focus,
//  in either bar.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

/// What the probes' actions did, reachable from an `App`.
private final class ReachProbe: @unchecked Sendable {
    static let shared = ReachProbe()
    var deletes = 0

    func reset() {
        deletes = 0
    }
}

/// A destructive button in the bottom bar, under a sheet.
private struct BottomButtonUnderSheetApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("PAGE")
                .toolbar {
                    ToolbarItem(placement: .bottomBar) {
                        Button("DELETE") { ReachProbe.shared.deletes += 1 }
                            .keyboardShortcut("d", modifiers: [])
                    }
                }
                .sheet(isPresented: .constant(true)) { Text("SHEET") }
        }
    }
}

/// A toolbar button declared inside a `.dimmed()` subtree, beside a live page.
private struct DimmedDeclarationApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            VStack {
                Button("LIVE") {}
                Text("RECESSIVE")
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("WIPE") { ReachProbe.shared.deletes += 1 }
                                .keyboardShortcut("d", modifiers: [])
                        }
                    }
                    .dimmed()
            }
        }
    }
}

@MainActor
@Suite("What reaches a toolbar item", .serialized)
struct ToolbarReachTests {

    /// Two frames: one that declares the bars, one that draws them.
    private func settled<A: App>(_ app: A, width: Int = 50, height: Int = 12) -> HeadlessApp<A> {
        let headless = HeadlessApp(app, width: width, height: height)
        headless.frame(atNanos: 0)
        headless.frame(atNanos: 20_000_000)
        return headless
    }

    /// Clicks the first cell of `text` on the screen.
    private func click(_ text: String, in app: HeadlessApp<some App>) throws {
        let rows = app.screen.map(\.stripped)
        let row = try #require(rows.firstIndex { $0.contains(text) }, "\(rows)")
        let column = rows[row].distance(
            from: rows[row].startIndex, to: try #require(rows[row].range(of: text)).lowerBound)
        app.send(MouseEvent(button: .left, phase: .pressed, x: column, y: row))
        app.send(MouseEvent(button: .left, phase: .released, x: column, y: row))
    }

    @Test("Under a modal a bottom-bar button is inert: its shortcut and its click do nothing")
    func bottomBarIsInertUnderAModal() throws {
        ReachProbe.shared.reset()
        let app = settled(BottomButtonUnderSheetApp())
        #expect(app.screen.contains { $0.stripped.contains("DELETE") }, "the bar is still drawn")
        app.send(KeyEvent(key: .character("d")))
        #expect(ReachProbe.shared.deletes == 0, "not by its key")
        try click("DELETE", in: app)
        #expect(ReachProbe.shared.deletes == 0, "nor by a click behind the sheet")
    }

    @Test("An item declared inside .dimmed() is drawn, but nothing reaches it")
    func dimmedDeclarationIsInert() throws {
        ReachProbe.shared.reset()
        let app = settled(DimmedDeclarationApp())
        #expect(app.screen.contains { $0.stripped.contains("WIPE") }, "\(app.screen.map(\.stripped))")
        app.send(KeyEvent(key: .character("d")))
        #expect(ReachProbe.shared.deletes == 0, "not by its key")
        try click("WIPE", in: app)
        #expect(ReachProbe.shared.deletes == 0, "nor by a click")
        app.send(KeyEvent(key: .tab))
        app.frame(atNanos: 40_000_000)
        app.send(KeyEvent(key: .tab))
        app.frame(atNanos: 60_000_000)
        app.send(KeyEvent(key: .enter))
        #expect(ReachProbe.shared.deletes == 0, "nor by Tab and Return")
    }
}
