//  🖥️ TUI — A Terminal UI framework for Swift
//  OptInChromeTests.swift
//
//  Every bar is the app's to place (A28): a bare `WindowGroup` draws on every
//  row of the terminal, the line of key hints appears only where the app puts
//  `StatusBar()`, and the keys it names — `q` above all — work with no bar.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
import TUIPresentation
@testable import TUITestSupport

/// A page that marks its first and last rows.
private struct BareApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                Text("FIRST")
                Spacer()
                Text("LAST")
            }
        }
    }
}

/// The same page with the line of key hints opted into.
private struct HintsApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            VStack(spacing: 0) {
                Text("FIRST")
                Spacer()
                Text("LAST")
            }
            .toolbar { ToolbarItem(placement: .bottomBar) { StatusBar() } }
        }
    }
}

/// Both bars, bordered: three rows each.
private struct BothBarsApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("PAGE")
                .toolbar {
                    ToolbarItem(placement: .navigation) { Text("HEADER") }
                    ToolbarItem(placement: .bottomBar) { StatusBar() }
                }
        }
    }
}

/// What the sheet probe's page did, reachable from an `App`.
private final class SheetProbe: @unchecked Sendable {
    static let shared = SheetProbe()
    var adds = 0
    var presented = true
}

/// A page with an item of its own and the line of key hints, under a sheet that
/// wraps the `.toolbar` — so the hints are drawn in the backdrop's environment.
private struct HintsUnderSheetApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("PAGE")
                .statusBarItems {
                    StatusBarItem(shortcut: "n", label: "new") { SheetProbe.shared.adds += 1 }
                }
                .toolbar { ToolbarItem(placement: .bottomBar) { StatusBar() } }
                .sheet(
                    isPresented: Binding(
                        get: { SheetProbe.shared.presented }, set: { SheetProbe.shared.presented = $0 })
                ) { Text("EDITOR") }
        }
    }
}

/// What the cut bar's button did, reachable from an `App`.
private final class CutBarProbe: @unchecked Sendable {
    static let shared = CutBarProbe()
    var deletes = 0
}

/// A toolbar item whose own `@State` counts its presses.
private struct TallyItem: View {
    @State private var count = 0

    var body: some View {
        Button("TALLY \(count)") { count += 1 }
            .keyboardShortcut("c", modifiers: [])
    }
}

/// A top bar with a button and a counter in it, over a boxed line of key
/// hints: in a terminal of three rows the bottom bar takes them all.
private struct CutTopBarApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("PAGE")
                .toolbar {
                    ToolbarItem(placement: .navigation) { TallyItem() }
                    ToolbarItem(placement: .primaryAction) {
                        Button("DEL") { CutBarProbe.shared.deletes += 1 }
                            .keyboardShortcut("d", modifiers: [])
                    }
                    ToolbarItem(placement: .bottomBar) { StatusBar() }
                }
        }
    }
}

@MainActor
@Suite("Chrome is opt-in", .serialized)
struct OptInChromeTests {

    @Test("A bare WindowGroup draws on every row of the terminal")
    func bareAppTakesEveryRow() {
        let harness = RenderLoopHarness()
        let loop = harness.loop(BareApp())
        _ = loop.render()
        let rows = loop.diffWriter.shownLines.map(\.stripped)
        #expect(rows.count == 24)
        #expect(rows.first?.contains("FIRST") == true, "\(rows)")
        #expect(rows.last?.contains("LAST") == true, "no bar takes the bottom rows: \(rows)")
        #expect(!rows.contains { $0.contains("quit") }, "no line of key hints unless placed")
    }

    @Test("StatusBar() in the bottom bar is the line of key hints, quit and all")
    func statusBarIsOptedInto() {
        let harness = RenderLoopHarness()
        let loop = harness.loop(HintsApp())
        _ = loop.render()
        let rows = loop.diffWriter.shownLines.map(\.stripped)
        #expect(rows[rows.count - 2].contains("Q quit"), "\(rows)")
        #expect(rows[rows.count - 4].contains("LAST"), "the page ends above the bar: \(rows)")
    }

    @Test("q quits with no bar on the screen")
    func quitWorksWithNoBar() {
        let harness = RenderLoopHarness()
        let loop = harness.loop(BareApp())
        _ = loop.render()
        var quits = 0
        let handler = InputHandler(
            statusBar: harness.statusBar,
            keyEventDispatcher: harness.tuiContext.keyEventDispatcher,
            focusManager: harness.focusManager,
            paletteManager: harness.paletteManager,
            appearanceManager: harness.appearanceManager,
            keyboardShortcuts: harness.tuiContext.keyboardShortcuts,
            dragAndDropSession: nil,
            onQuit: { quits += 1 },
            onSuspend: {})
        _ = handler.handle(KeyEvent(key: .character("q")))
        #expect(quits == 1)
    }

    @Test("In a terminal too short for both bars, the bottom bar stays whole and the top bar gives way")
    func shortTerminalKeepsTheBottomBar() {
        let app = HeadlessApp(BothBarsApp(), width: 40, height: 4)
        app.frame(atNanos: 0)
        app.frame(atNanos: 20_000_000)
        let rows = app.screen.map(\.stripped)
        #expect(rows.count == 4, "\(rows)")
        #expect(rows[0].hasPrefix("╭"), "the top bar's first row is all of it there is room for: \(rows)")
        #expect(rows[1].hasPrefix("╭"), "the bottom bar's top border: \(rows)")
        #expect(rows[2].contains("Q quit"), "the line of key hints is on the screen: \(rows)")
        #expect(rows[3].hasPrefix("╰"), "and the bar is closed: \(rows)")
    }

    @Test(
        "A bar the terminal shows none of the rows of has no live item: no shortcut, no Tab stop",
        arguments: [3, 4])
    func cutBarHasNoLiveItem(height: Int) {
        CutBarProbe.shared.deletes = 0
        let app = HeadlessApp(CutTopBarApp(), width: 40, height: height)
        app.frame(atNanos: 0)
        app.frame(atNanos: 20_000_000)
        let rows = app.screen.map(\.stripped)
        #expect(rows.contains { $0.contains("Q quit") }, "sanity: the bottom bar is whole: \(rows)")
        #expect(!rows.contains { $0.contains("DEL") }, "sanity: the top bar's item row is cut off: \(rows)")
        app.send(KeyEvent(key: .character("d")))
        #expect(CutBarProbe.shared.deletes == 0, "the button nobody can see is not on its key")
        app.send(KeyEvent(key: .tab))
        app.frame(atNanos: 40_000_000)
        app.send(KeyEvent(key: .enter))
        #expect(CutBarProbe.shared.deletes == 0, "nor reached by Tab and Return")
    }

    @Test("A bar cut short but showing its item row keeps its items live")
    func cutBarShowingItsItemsIsLive() {
        CutBarProbe.shared.deletes = 0
        let app = HeadlessApp(CutTopBarApp(), width: 40, height: 5)
        app.frame(atNanos: 0)
        app.frame(atNanos: 20_000_000)
        let rows = app.screen.map(\.stripped)
        #expect(rows[1].contains("DEL"), "the top bar's wall and its item row: \(rows)")
        app.send(KeyEvent(key: .character("d")))
        #expect(CutBarProbe.shared.deletes == 1)
    }

    @Test("A bar cut off by a short terminal keeps its items' @State for when the terminal grows")
    func cutBarKeepsItsItemsState() {
        let app = HeadlessApp(CutTopBarApp(), width: 40, height: 10)
        var now: Int64 = 0
        func frame() {
            app.frame(atNanos: now)
            now += 20_000_000
        }
        frame()
        frame()
        app.send(KeyEvent(key: .character("c")))
        frame()
        app.send(KeyEvent(key: .character("c")))
        frame()
        #expect(app.screen.contains { $0.stripped.contains("TALLY 2") }, "sanity: \(app.screen.map(\.stripped))")
        app.resize(width: 40, height: 3)
        frame()
        frame()
        #expect(!app.screen.contains { $0.stripped.contains("TALLY") }, "sanity: cut off")
        app.resize(width: 40, height: 10)
        frame()
        frame()
        let rows = app.screen.map(\.stripped)
        #expect(rows.contains { $0.contains("TALLY 2") }, "\(rows)")
    }

    @Test("Under a sheet, StatusBar() is the app's line — the sheet's keys — and a click on one does what it says")
    func hintsUnderASheetAreTheSheets() throws {
        SheetProbe.shared.adds = 0
        SheetProbe.shared.presented = true
        let app = HeadlessApp(HintsUnderSheetApp(), width: 50, height: 10)
        app.frame(atNanos: 0)
        app.frame(atNanos: 20_000_000)
        let rows = app.screen.map(\.stripped)
        let line = rows[rows.count - 2]
        #expect(line.contains("dismiss"), "the sheet's Escape: \(rows)")
        #expect(!line.contains("new"), "not the page's item, which does nothing behind the sheet: \(rows)")
        let column = line.distance(from: line.startIndex, to: try #require(line.range(of: "dismiss")).lowerBound)
        app.send(MouseEvent(button: .left, phase: .pressed, x: column, y: rows.count - 2))
        app.send(MouseEvent(button: .left, phase: .released, x: column, y: rows.count - 2))
        #expect(!SheetProbe.shared.presented, "the click dismissed the sheet")
        #expect(SheetProbe.shared.adds == 0)
    }
}
