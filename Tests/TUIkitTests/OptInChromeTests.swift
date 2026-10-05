//  🖥️ TUIkit — Terminal UI Kit for Swift
//  OptInChromeTests.swift
//
//  Every bar is the app's to place (A28): a bare `WindowGroup` draws on every
//  row of the terminal, the line of key hints appears only where the app puts
//  `StatusBar()`, and the keys it names — `q` above all — work with no bar.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkit
@testable import TUIkitCore

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
        #expect(rows[rows.count - 2].contains("q quit"), "\(rows)")
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
        #expect(rows[2].contains("q quit"), "the line of key hints is on the screen: \(rows)")
        #expect(rows[3].hasPrefix("╰"), "and the bar is closed: \(rows)")
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
