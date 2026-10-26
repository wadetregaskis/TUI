//  🖥️ TUI — A Terminal UI framework for Swift
//  ToolbarTests.swift
//
//  SwiftUI's `.toolbar` in a terminal: items join the window's top and bottom
//  bars by placement, are drawn in the environment and at the identity of the
//  view that declared them, sit after the page in the Tab ring, keep their
//  shortcuts, and go inert under a modal.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIChrome
@testable import TUICore
@testable import TUIFoundation
import TUIPresentation
@testable import TUITestSupport

/// What the probes' actions did, reachable from an `App`.
private final class ToolbarProbe: @unchecked Sendable {
    static let shared = ToolbarProbe()
    var saves = 0
    var presented = false

    func reset() {
        saves = 0
        presented = false
    }
}

/// One item in each placement the bars distinguish.
private struct PlacementsApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("PAGE")
                .navigationTitle("TITLE")
                .toolbar {
                    ToolbarItem(placement: .navigation) { Text("NAV") }
                    ToolbarItem(placement: .primaryAction) { Text("PRIMARY") }
                    ToolbarItem(placement: .secondaryAction) { Text("SECONDARY") }
                    ToolbarItem(placement: .bottomBar) { Text("BOTTOM") }
                    ToolbarItem(placement: .status) { Text("STATUS") }
                }
        }
    }
}

/// A principal item, which takes the title's place.
private struct PrincipalApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("PAGE")
                .navigationTitle("TITLE")
                .toolbar {
                    ToolbarItem(placement: .principal) { Text("MIDDLE") }
                }
        }
    }
}

/// A page button and a toolbar button with a shortcut, optionally disabled
/// from above the `.toolbar`, optionally under a sheet.
private struct ButtonsApp: App {
    var disabled = false
    var sheet = false

    init() {}

    init(disabled: Bool = false, sheet: Bool = false) {
        self.disabled = disabled
        self.sheet = sheet
    }

    var body: some Scene {
        WindowGroup {
            Button("PAGE-BUTTON") {}
                .sheet(isPresented: .constant(sheet)) { Text("SHEET") }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button("SAVE") { ToolbarProbe.shared.saves += 1 }
                            .keyboardShortcut("s", modifiers: [])
                    }
                }
                .disabled(disabled)
        }
    }
}

/// A toolbar item whose own `@State` counts its presses.
private struct CounterItem: View {
    @State private var count = 0

    var body: some View {
        Button("COUNT \(count)") { count += 1 }
            .keyboardShortcut("c", modifiers: [])
    }
}

private struct StatefulItemApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("PAGE")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) { CounterItem() }
                }
        }
    }
}

/// A page that is memoised, with its toolbar declared inside the memo.
private struct MemoisedPage: View, Equatable {
    var body: some View {
        Text("PAGE")
            .toolbar {
                ToolbarItem(placement: .primaryAction) { Text("ITEM") }
            }
    }
}

private struct MemoisedApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            MemoisedPage().equatable()
        }
    }
}

/// A foreground style written above the `.toolbar`.
private struct StyledApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("PAGE")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) { Text("TINTED") }
                }
                .foregroundStyle(Color.red)
        }
    }
}

@MainActor
@Suite("Toolbars", .serialized)
struct ToolbarTests {

    /// The screen's rows, escapes stripped.
    private func rows(_ app: HeadlessApp<some App>) -> [String] {
        app.screen.map(\.stripped)
    }

    /// Two frames: one that declares the bars, one that draws them.
    private func settled<A: App>(_ app: A, width: Int = 60, height: Int = 16) -> HeadlessApp<A> {
        let headless = HeadlessApp(app, width: width, height: height)
        headless.frame(atNanos: 0)
        headless.frame(atNanos: 20_000_000)
        return headless
    }

    @Test("Each placement lands in its bar and its place in it")
    func placements() throws {
        let screen = rows(settled(PlacementsApp()))
        // Bordered by default: row 1 is the top bar's content, the last but one
        // the bottom bar's.
        let top = screen[1]
        let bottom = screen[screen.count - 2]
        let nav = try #require(top.range(of: "NAV"), "\(screen)")
        let title = try #require(top.range(of: "TITLE"), "\(screen)")
        let secondary = try #require(top.range(of: "SECONDARY"), "\(screen)")
        let primary = try #require(top.range(of: "PRIMARY"), "\(screen)")
        #expect(nav.lowerBound < title.lowerBound, "navigation leads, the title follows: \(top)")
        #expect(title.lowerBound < secondary.lowerBound, "the trailing items are after the title: \(top)")
        #expect(secondary.lowerBound < primary.lowerBound, "secondary before primary: \(top)")
        #expect(top.hasSuffix("PRIMARY │"), "primary at the trailing end: \(top)")
        #expect(bottom.contains("BOTTOM") && bottom.contains("STATUS"), "the bottom bar: \(screen)")
        #expect(!top.contains("BOTTOM") && !top.contains("STATUS"))
        #expect(!bottom.contains("TITLE"), "the title is the top bar's: \(bottom)")
    }

    @Test("A principal item takes the title's place, in the middle of the bar")
    func principalReplacesTitle() throws {
        let screen = rows(settled(PrincipalApp()))
        let top = screen[1]
        #expect(!top.contains("TITLE"), "\(top)")
        let middle = try #require(top.range(of: "MIDDLE"), "\(screen)")
        let column = top.distance(from: top.startIndex, to: middle.lowerBound)
        #expect(abs(column - (60 - 6) / 2) <= 2, "centred: column \(column) of \(top)")
    }

    @Test("No item, no bar: a title alone draws no top bar")
    func titleAloneDrawsNoBar() {
        struct TitleOnly: App {
            init() {}
            var body: some Scene { WindowGroup { Text("PAGE").navigationTitle("TITLE") } }
        }
        let screen = rows(settled(TitleOnly()))
        #expect(!screen.contains { $0.contains("TITLE") }, "\(screen)")
    }

    @Test("A hidden item takes no room, and a bar of hidden items is not drawn")
    func hiddenItems() {
        struct HiddenApp: App {
            init() {}
            var body: some Scene {
                WindowGroup {
                    Text("PAGE").toolbar {
                        ToolbarItem { Text("GONE") }.hidden()
                        ToolbarItem(placement: .bottomBar) { Text("SHOWN") }
                        ToolbarItem(placement: .bottomBar) { Text("ALSO-GONE") }.hidden(true)
                    }
                }
            }
        }
        let screen = rows(settled(HiddenApp()))
        #expect(!screen.contains { $0.contains("GONE") }, "\(screen)")
        #expect(screen.contains { $0.contains("SHOWN") }, "\(screen)")
        #expect(screen[1].contains("PAGE") || !screen[0].contains("╭"), "no top bar: \(screen)")
    }

    @Test("A toolbar's controls are after the page's in the Tab ring, and never take the first focus")
    func focusRingOrder() {
        let harness = RenderLoopHarness()
        let loop = harness.loop(ButtonsApp())
        _ = loop.render()
        _ = loop.render()
        let ring = harness.focusManager.focusableIDs
        #expect(ring.count == 2, "\(ring)")
        #expect(harness.focusManager.currentFocusedID == ring.first, "the page's button has the focus")
        #expect(
            harness.focusManager.sectionIDs.last == _WindowChromeHost<EmptyView>.toolbarSectionID(.top),
            "the toolbar's section comes after the page's: \(harness.focusManager.sectionIDs)")
    }

    @Test("A toolbar item's keyboard shortcut fires")
    func shortcutsFire() {
        ToolbarProbe.shared.reset()
        let app = settled(ButtonsApp())
        app.send(KeyEvent(key: .character("s")))
        #expect(ToolbarProbe.shared.saves == 1)
    }

    @Test("A disabled above the toolbar disables its items")
    func disabledReachesItems() {
        ToolbarProbe.shared.reset()
        let app = settled(ButtonsApp(disabled: true))
        app.send(KeyEvent(key: .character("s")))
        #expect(ToolbarProbe.shared.saves == 0, "a disabled button's shortcut does nothing")
    }

    @Test("Under a modal the top bar is inert: its shortcuts and clicks do nothing")
    func inertUnderModal() throws {
        ToolbarProbe.shared.reset()
        let app = settled(ButtonsApp(sheet: true))
        app.send(KeyEvent(key: .character("s")))
        #expect(ToolbarProbe.shared.saves == 0, "the shortcut is not live behind the sheet")
        let screen = rows(app)
        let row = try #require(screen.firstIndex { $0.contains("SAVE") }, "\(screen)")
        let column = screen[row].distance(
            from: screen[row].startIndex, to: try #require(screen[row].range(of: "SAVE")).lowerBound)
        app.send(MouseEvent(button: .left, phase: .pressed, x: column, y: row))
        app.send(MouseEvent(button: .left, phase: .released, x: column, y: row))
        #expect(ToolbarProbe.shared.saves == 0, "nor a click")
    }

    @Test("A click on a toolbar button fires it")
    func clicksFire() throws {
        ToolbarProbe.shared.reset()
        let app = settled(ButtonsApp())
        let screen = rows(app)
        let row = try #require(screen.firstIndex { $0.contains("SAVE") }, "\(screen)")
        let column = screen[row].distance(
            from: screen[row].startIndex, to: try #require(screen[row].range(of: "SAVE")).lowerBound)
        app.send(MouseEvent(button: .left, phase: .pressed, x: column, y: row))
        app.send(MouseEvent(button: .left, phase: .released, x: column, y: row))
        #expect(ToolbarProbe.shared.saves == 1)
    }

    @Test("A toolbar item keeps its @State from frame to frame")
    func itemStateSurvives() {
        let app = settled(StatefulItemApp())
        #expect(rows(app).contains { $0.contains("COUNT 0") }, "\(rows(app))")
        app.send(KeyEvent(key: .character("c")))
        app.frame(atNanos: 40_000_000)
        app.send(KeyEvent(key: .character("c")))
        app.frame(atNanos: 60_000_000)
        #expect(rows(app).contains { $0.contains("COUNT 2") }, "\(rows(app))")
    }

    @Test("A foreground style above the toolbar reaches its items")
    func foregroundStyleReachesItems() throws {
        let app = HeadlessApp(StyledApp(), width: 40, height: 10)
        ColorDepth.withCurrent(.truecolor) {
            app.frame(atNanos: 0)
            app.frame(atNanos: 20_000_000)
        }
        let item = try #require(app.screen.first { $0.stripped.contains("TINTED") })
        let page = try #require(app.screen.first { $0.stripped.contains("PAGE") })
        let itemStyle = try #require(styleBefore("TINTED", in: item))
        let pageStyle = try #require(styleBefore("PAGE", in: page))
        #expect(itemStyle.foregroundColour != nil, "the item is drawn in a colour")
        #expect(
            itemStyle.foregroundColour == pageStyle.foregroundColour,
            "the item takes the page's red: \(itemStyle.rendered.debugDescription) vs \(pageStyle.rendered.debugDescription)")
    }

    /// The styling in force where `text` starts in `line`.
    private func styleBefore(_ text: String, in line: String) -> SGRState? {
        guard let range = line.range(of: text) else { return nil }
        var state = SGRState()
        let scalars = Array(line[..<range.lowerBound].unicodeScalars)
        var index = 0
        while index < scalars.count {
            guard scalars[index] == "\u{1B}", index + 1 < scalars.count, scalars[index + 1] == "[" else {
                index += 1
                continue
            }
            var end = index + 2
            while end < scalars.count, !(0x40...0x7E).contains(scalars[end].value) { end += 1 }
            if end < scalars.count, scalars[end] == "m" {
                var sequence = ""
                sequence.unicodeScalars.append(contentsOf: scalars[index...end])
                state.apply(sequence)
            }
            index = end + 1
        }
        return state
    }

    @Test("A toolbar under a memoised view is declared every frame, and the memo verifier is clean")
    func memoisedDeclarationIsClean() {
        let was = RenderCache.verifiesRenderMemo
        defer { RenderCache.verifiesRenderMemo = was }
        RenderCache.verifiesRenderMemo = true
        let harness = RenderLoopHarness()
        let loop = harness.loop(MemoisedApp())
        for _ in 0..<4 { _ = loop.render() }
        #expect(loop.diffWriter.shownLines.contains { $0.stripped.contains("ITEM") })
        #expect(harness.tuiContext.renderCache.renderMemoMismatches.isEmpty, "\(harness.tuiContext.renderCache.renderMemoMismatches)")
    }
}
