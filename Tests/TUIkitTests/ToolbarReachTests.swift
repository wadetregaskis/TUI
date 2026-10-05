//  🖥️ TUIkit — Terminal UI Kit for Swift
//  ToolbarReachTests.swift
//
//  What a toolbar item can be reached by, and when: an item drawn inert —
//  under a modal, or declared by a backdrop — keeps no click, key or focus,
//  in either bar; a render nobody sees declares nothing at all.
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
    var pushed = false

    func reset() {
        deletes = 0
        pushed = false
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

/// A stack whose root declares a toolbar button, a bottom bar it hides, and a
/// line of key hints declared around the stack — with a screen pushed over the
/// root when ``ReachProbe/pushed`` says so.
private struct CoveredRootApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            NavigationStack(
                path: .constant(ReachProbe.shared.pushed ? [1] : [Int]())
            ) {
                Text("ROOT")
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button("WIPE") { ReachProbe.shared.deletes += 1 }
                                .keyboardShortcut("d", modifiers: [])
                        }
                    }
                    .toolbarVisibility(.hidden, for: .bottomBar)
                    .navigationDestination(for: Int.self) { Text("DETAIL \($0)") }
            }
            .toolbar { ToolbarItem(placement: .bottomBar) { StatusBar() } }
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

    @Test("A navigation stack's covered root puts nothing in the window's bars")
    func coveredRootDeclaresNothing() {
        ReachProbe.shared.reset()
        let shown = settled(CoveredRootApp())
        #expect(shown.screen.contains { $0.stripped.contains("WIPE") }, "sanity: the root's item, while it shows")
        shown.send(KeyEvent(key: .character("d")))
        #expect(ReachProbe.shared.deletes == 1, "sanity: and its shortcut")

        ReachProbe.shared.reset()
        ReachProbe.shared.pushed = true
        defer { ReachProbe.shared.pushed = false }
        let covered = settled(CoveredRootApp())
        let rows = covered.screen.map(\.stripped)
        #expect(rows.contains { $0.contains("DETAIL 1") }, "sanity: the pushed screen: \(rows)")
        #expect(!rows.contains { $0.contains("WIPE") }, "the covered root's item is not drawn: \(rows)")
        covered.send(KeyEvent(key: .character("d")))
        #expect(ReachProbe.shared.deletes == 0, "nor is its shortcut live")
    }

    @Test("A navigation stack's covered root does not hide a bar")
    func coveredRootHidesNoBar() {
        ReachProbe.shared.reset()
        let shown = settled(CoveredRootApp())
        #expect(!shown.screen.contains { $0.stripped.contains("q quit") }, "sanity: the root hides the hints")

        ReachProbe.shared.pushed = true
        defer { ReachProbe.shared.pushed = false }
        let covered = settled(CoveredRootApp())
        let rows = covered.screen.map(\.stripped)
        #expect(rows.contains { $0.contains("q quit") }, "the pushed screen has its bottom bar: \(rows)")
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
