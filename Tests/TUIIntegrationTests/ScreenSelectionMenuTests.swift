//  🖥️ TUI — A Terminal UI framework for Swift
//  ScreenSelectionMenuTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUI
@testable import TUIApp
@testable import TUICore
@testable import TUIFoundation
@testable import TUITestSupport

@MainActor
@Suite("Screen selection: its context menu")
struct ScreenSelectionMenuTests {
    struct Page: App {
        var body: some Scene {
            WindowGroup {
                VStack(alignment: .leading) {
                    Text("alpha beta gamma")
                    Text("second row text")
                }
            }
        }
    }

    final class Clock {
        var nanos: Int64 = 1_000_000_000
    }

    /// An app with `alpha` selected, its copies going to `log`.
    func selected(log: SystemClipboardLog) throws -> (HeadlessApp, Clock, x: Int, y: Int) {
        let app = HeadlessApp(Page(), width: 40, height: 10)
        app.services.clipboardWriter = ClipboardWriter.stated(terminal: .unsupported, isLocal: true, log: log)
        let clock = Clock()
        func frame() {
            clock.nanos += 16_666_667
            app.frame(atNanos: clock.nanos)
        }
        frame()
        frame()
        let lines = app.screen.map(\.stripped)
        let y = try #require(lines.firstIndex { $0.contains("alpha") })
        let x = lines[y][..<(try #require(lines[y].range(of: "alpha")).lowerBound)].count
        app.send(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        frame()
        app.send(MouseEvent(button: .left, phase: .dragged, x: x + 4, y: y))
        frame()
        app.send(MouseEvent(button: .left, phase: .released, x: x + 4, y: y))
        frame()
        return (app, clock, x, y)
    }

    func frame(_ app: HeadlessApp, _ clock: Clock) {
        clock.nanos += 16_666_667
        app.frame(atNanos: clock.nanos)
    }

    var copyTitle: String { LocalizationService.shared.string(for: LocalizationKey.Button.copy) }

    @Test("A right-click on the highlight offers Copy, and choosing it copies and closes the menu")
    func rightClickOffersCopy() throws {
        let log = SystemClipboardLog()
        let (app, clock, x, y) = try selected(log: log)
        #expect(app.services.screenSelection.current?.text == "alpha")
        #expect(app.send(MouseEvent(button: .right, phase: .pressed, x: x + 1, y: y)))
        app.send(MouseEvent(button: .right, phase: .released, x: x + 1, y: y))
        frame(app, clock)
        #expect(app.screen.map(\.stripped).contains { $0.contains(copyTitle) })
        // A menu the pointer opened highlights nothing until a key moves in.
        app.send(KeyEvent(key: .down))
        frame(app, clock)
        app.send(KeyEvent(key: .enter))
        frame(app, clock)
        #expect(log.writes == ["alpha"])
        #expect(app.services.screenSelection.menuAnchor == nil)
        #expect(!app.screen.map(\.stripped).contains { $0.contains(copyTitle) })
        // The selection outlives its menu, as on a Mac.
        #expect(app.services.screenSelection.hasSelection)
    }

    /// As `.contextMenu`'s: press, slide down onto the row with the button
    /// held, release on it.
    @Test("A right press held and dragged onto Copy highlights it, and the release there copies")
    func heldDragTracks() throws {
        let log = SystemClipboardLog()
        let (app, clock, x, y) = try selected(log: log)
        app.send(MouseEvent(button: .right, phase: .pressed, x: x + 1, y: y))
        frame(app, clock)
        let lines = app.screen.map(\.stripped)
        let row = try #require(lines.firstIndex { $0.contains(copyTitle) })
        let column = lines[row][..<(try #require(lines[row].range(of: copyTitle)).lowerBound)].count
        app.send(MouseEvent(button: .right, phase: .dragged, x: column + 1, y: row))
        frame(app, clock)
        #expect(app.services.screenSelection.menuController?.highlightedOrdinal == 0)
        app.send(MouseEvent(button: .right, phase: .released, x: column + 1, y: row))
        frame(app, clock)
        #expect(log.writes == ["alpha"])
        #expect(app.services.screenSelection.menuAnchor == nil)
    }

    @Test("Escape closes the menu and keeps the selection")
    func escapeClosesTheMenu() throws {
        let log = SystemClipboardLog()
        let (app, clock, x, y) = try selected(log: log)
        app.send(MouseEvent(button: .right, phase: .pressed, x: x, y: y))
        frame(app, clock)
        app.send(KeyEvent(key: .escape))
        frame(app, clock)
        #expect(app.services.screenSelection.menuAnchor == nil)
        #expect(app.services.screenSelection.hasSelection)
        #expect(log.writes.isEmpty)
    }

    @Test("The highlight is still drawn when the menu over it closes, and opens it again")
    func menuLeavesTheHighlight() throws {
        let (app, clock, x, y) = try selected(log: SystemClipboardLog())
        app.send(MouseEvent(button: .right, phase: .pressed, x: x, y: y))
        frame(app, clock)
        app.send(KeyEvent(key: .escape))
        frame(app, clock)
        #expect(app.services.screenSelection.current?.isHighlighted == true)
        #expect(app.send(MouseEvent(button: .right, phase: .pressed, x: x, y: y)))
        #expect(app.services.screenSelection.menuAnchor != nil)
    }

    struct AlertPage: App {
        struct Content: View {
            @State private var showing = false
            var body: some View {
                VStack(alignment: .leading) {
                    Text("alpha beta gamma")
                    Button("Show") { showing = true }
                }
                .alert("Shown", isPresented: $showing) {
                    Button("OK") {}
                }
            }
        }

        var body: some Scene {
            WindowGroup { Content() }
        }
    }

    /// What is under a modal's backdrop is not the user's to copy, and the
    /// keys are the presentation's.
    @Test("A presentation clears the selection")
    func presentationClears() throws {
        let app = HeadlessApp(AlertPage(), width: 40, height: 12)
        let clock = Clock()
        func frame() {
            clock.nanos += 16_666_667
            app.frame(atNanos: clock.nanos)
        }
        frame()
        frame()
        let lines = app.screen.map(\.stripped)
        let y = try #require(lines.firstIndex { $0.contains("alpha") })
        let x = lines[y][..<(try #require(lines[y].range(of: "alpha")).lowerBound)].count
        app.send(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        app.send(MouseEvent(button: .left, phase: .dragged, x: x + 4, y: y))
        app.send(MouseEvent(button: .left, phase: .released, x: x + 4, y: y))
        frame()
        #expect(app.services.screenSelection.hasSelection)
        // The button holds the focus; Return shows the alert.
        app.send(KeyEvent(key: .enter))
        frame()
        frame()
        #expect(app.screen.map(\.stripped).contains { $0.contains("Shown") })
        #expect(!app.services.screenSelection.hasSelection)
    }

    @Test("A right-click off the highlight is not the selection's")
    func rightClickElsewhere() throws {
        let (app, clock, x, y) = try selected(log: SystemClipboardLog())
        app.send(MouseEvent(button: .right, phase: .pressed, x: x + 10, y: y))
        frame(app, clock)
        #expect(app.services.screenSelection.menuAnchor == nil)
        #expect(!app.screen.map(\.stripped).contains { $0.contains(copyTitle) })
    }

    /// The same page under a window top bar: the pointer's rows are the
    /// screen's, the selection's the page's.
    struct BarredPage: App {
        var body: some Scene {
            WindowGroup {
                VStack(alignment: .leading) {
                    Text("alpha beta gamma")
                    Text("second row text")
                }
                .toolbar { ToolbarItem(placement: .primaryAction) { Text("TOP") } }
            }
        }
    }

    /// Selects `second` with a drag, opens the selection's menu on it and
    /// chooses Copy: whether a top bar was drawn above, what was selected and
    /// copied, and how many rows below the clicked row the menu's Copy was.
    func copySecond<A: App>(_ page: A) throws -> (barDrawn: Bool, selected: String?, copied: [String], menuBelow: Int) {
        let log = SystemClipboardLog()
        let app = HeadlessApp(page, width: 40, height: 12)
        app.services.clipboardWriter = ClipboardWriter.stated(terminal: .unsupported, isLocal: true, log: log)
        let clock = Clock()
        func frame() {
            clock.nanos += 16_666_667
            app.frame(atNanos: clock.nanos)
        }
        frame()
        frame()
        let lines = app.screen.map(\.stripped)
        let y = try #require(lines.firstIndex { $0.contains("second") })
        let x = lines[y][..<(try #require(lines[y].range(of: "second")).lowerBound)].count
        app.send(MouseEvent(button: .left, phase: .pressed, x: x, y: y))
        app.send(MouseEvent(button: .left, phase: .dragged, x: x + 5, y: y))
        app.send(MouseEvent(button: .left, phase: .released, x: x + 5, y: y))
        frame()
        let selected = app.services.screenSelection.current?.text
        app.send(MouseEvent(button: .right, phase: .pressed, x: x + 1, y: y))
        app.send(MouseEvent(button: .right, phase: .released, x: x + 1, y: y))
        frame()
        let menuRow = try #require(app.screen.map(\.stripped).firstIndex { $0.contains(copyTitle) })
        app.send(KeyEvent(key: .down))
        frame()
        app.send(KeyEvent(key: .enter))
        frame()
        return (lines[..<y].contains { $0.contains("TOP") }, selected, log.writes, menuRow - y)
    }

    /// The pointer and the hit regions are in the screen's rows, the selection
    /// and its menu's anchor in the page's: under a bar the two differ by the
    /// bar's rows.
    @Test("Under a window's top bar a drag selects the cells under the pointer, and Copy opens where it was clicked")
    func underATopBar() throws {
        let bare = try copySecond(Page())
        let barred = try copySecond(BarredPage())
        #expect(!bare.barDrawn && barred.barDrawn)
        #expect(barred.selected == "second")
        #expect(barred.copied == ["second"])
        #expect(barred.menuBelow == bare.menuBelow)
    }
}
