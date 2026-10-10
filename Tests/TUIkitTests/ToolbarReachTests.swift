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

import TUIkit
@testable import TUIkitApp
@testable import TUIkitChrome
@testable import TUIkitCore
@testable import TUIkitFoundation
@testable import TUIkitTestSupport

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

/// A toolbar item whose own `@State` counts its presses.
private struct TallyItem: View {
    @State private var count = 0

    var body: some View {
        Button("TALLY \(count)") { count += 1 }
            .keyboardShortcut("c", modifiers: [])
    }
}

/// A stack whose root's toolbar holds an item with state of its own, with a
/// screen pushed over the root when ``ReachProbe/pushed`` says so.
private struct CoveredRootStateApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            NavigationStack(
                path: .constant(ReachProbe.shared.pushed ? [1] : [Int]())
            ) {
                Text("ROOT")
                    .toolbar { ToolbarItem(placement: .primaryAction) { TallyItem() } }
                    .navigationDestination(for: Int.self) { Text("DETAIL \($0)") }
            }
        }
    }
}

/// A windowed stack whose focused first row is a long way above the next
/// focusable one, with a row between them — off the screen — that declares a
/// toolbar button: the rows the focus-reach probe renders to find the next
/// stop, and the frame never draws.
private struct ProbedRowsApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<60, id: \.self) { index in
                        if index == 0 || index == 40 {
                            Button("ROW \(index)") {}
                        } else if index == 25 {
                            Text("ROW 25")
                                .toolbar {
                                    ToolbarItem(placement: .primaryAction) {
                                        Button("LEAK") { ReachProbe.shared.deletes += 1 }
                                            .keyboardShortcut("d", modifiers: [])
                                    }
                                }
                        } else {
                            Text("ROW \(index)")
                        }
                    }
                }
            }
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

/// Whether the loading page has loaded: reachable from an `App`.
private final class LoadSwitch: @unchecked Sendable {
    static let shared = LoadSwitch()
    var loaded = false
}

/// A page with nothing to focus until it loads, under a bottom bar.
private struct LoadingPageApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            VStack {
                if LoadSwitch.shared.loaded {
                    Button("FIRST") {}
                    Button("SECOND") {}
                } else {
                    Text("LOADING")
                }
            }
            .toolbar {
                ToolbarItem(placement: .bottomBar) { StatusBar() }
                ToolbarItem(placement: .bottomBar) { Button("BAR") {} }
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

    @Test("A navigation stack's covered root keeps its toolbar items' @State while a screen is pushed over it")
    func coveredRootKeepsItsItemsState() {
        ReachProbe.shared.reset()
        defer { ReachProbe.shared.pushed = false }
        let app = settled(CoveredRootStateApp())
        var now: Int64 = 20_000_000
        func frames(_ count: Int = 2) {
            for _ in 0..<count {
                now += 20_000_000
                app.frame(atNanos: now)
            }
        }
        for _ in 0..<3 {
            app.send(KeyEvent(key: .character("c")))
            frames(1)
        }
        #expect(app.screen.contains { $0.stripped.contains("TALLY 3") }, "sanity: \(app.screen.map(\.stripped))")

        ReachProbe.shared.pushed = true
        frames()
        #expect(app.screen.contains { $0.stripped.contains("DETAIL 1") }, "sanity: pushed")
        #expect(!app.screen.contains { $0.stripped.contains("TALLY") }, "sanity: the root's item is not drawn")

        ReachProbe.shared.pushed = false
        frames()
        let rows = app.screen.map(\.stripped)
        #expect(rows.contains { $0.contains("TALLY 3") }, "popped, the item has its count: \(rows)")
    }

    @Test("Rows the focus-reach probe walks past put nothing in the window's bars")
    func probedRowsDeclareNothing() {
        ReachProbe.shared.reset()
        let app = settled(ProbedRowsApp())
        app.frame(atNanos: 40_000_000)
        let rows = app.screen.map(\.stripped)
        #expect(rows.contains { $0.contains("ROW 0") }, "sanity: \(rows)")
        #expect(!rows.contains { $0.contains("ROW 25") }, "sanity: row 25 is off the screen: \(rows)")
        #expect(!rows.contains { $0.contains("LEAK") }, "its item is not in a bar: \(rows)")
        app.send(KeyEvent(key: .character("d")))
        #expect(ReachProbe.shared.deletes == 0, "nor is its shortcut live")
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

    @Test("A bar never takes the keyboard: controls the page gains after the bar was drawn get the focus")
    func barNeverTakesTheKeyboard() throws {
        LoadSwitch.shared.loaded = false
        defer { LoadSwitch.shared.loaded = false }
        let harness = RenderLoopHarness()
        let loop = harness.loop(LoadingPageApp())
        _ = loop.render()
        _ = loop.render()
        #expect(harness.focusManager.currentFocusedID == nil, "nothing to focus but the bar's, which it never takes")
        LoadSwitch.shared.loaded = true
        _ = loop.render()
        _ = loop.render()
        let ring = harness.focusManager.focusableIDs
        #expect(ring.count == 3, "\(ring)")
        #expect(harness.focusManager.currentFocusedID == ring.first, "the page's first control: \(ring)")
        #expect(
            harness.focusManager.activeSectionIdentifier != _WindowChromeHost<EmptyView>.toolbarSectionID(.bottom),
            "the page's section holds the keyboard")
    }
}
