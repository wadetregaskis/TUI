//  🖥️ TUIkit — Terminal UI Kit for Swift
//  StatusBarFrameDiffTests.swift
//
//  The status bar through a whole frame — `RenderLoop.render` into a
//  `MockTerminal`, read back row by row — rather than through
//  `StatusBar.renderToBuffer`, which is where every earlier bar test stopped.
//  What broke here lived between the view and the terminal: in what the frame
//  diff believed was already on screen, and in whether the loop built the bar
//  at all.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

import TUIkit
@testable import TUIkitApp
@testable import TUIkitCore
@testable import TUIkitFoundation

/// A page of one line of text with the line of key hints in its bottom bar, so
/// the rows the tests read are the bar's.
private struct StatusBarProbeApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("content")
                .toolbar { ToolbarItem(placement: .bottomBar) { StatusBar() } }
        }
    }
}

/// A page that states one status bar item of its own.
private struct StatusBarItemsProbeApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("content")
                .statusBarItems {
                    StatusBarItem(shortcut: "q", label: "Quit")
                }
                .toolbar { ToolbarItem(placement: .bottomBar) { StatusBar() } }
        }
    }
}

/// A page that declares a status bar item and nothing else puts one there.
private struct DeclaredItemProbeApp: App {
    init() {}

    var body: some Scene {
        WindowGroup {
            Text("content")
                .statusBarItems {
                    StatusBarItem(shortcut: "s", label: "save")
                }
                .toolbar { ToolbarItem(placement: .bottomBar) { StatusBar() } }
        }
    }
}

@MainActor
@Suite("The status bar reaches the terminal")
struct StatusBarFrameDiffTests {

    /// Everything written to each terminal row since the terminal was last reset,
    /// escapes stripped, keyed by the row of the cursor move before it.
    ///
    /// Accumulated rather than last-write-wins — the weaker oracle, on purpose, and
    /// still enough: a row the frame never visited is ABSENT and a row it only
    /// erased is blank, and those are the two ways the bar went missing.
    private func paints(_ terminal: MockTerminal) -> [Int: String] {
        var rows: [Int: String] = [:]
        var current: Int?
        for chunk in terminal.writtenOutput {
            if let moved = cursorRow(chunk) {
                current = moved
                if rows[moved] == nil { rows[moved] = "" }
            } else if let current {
                rows[current, default: ""] += chunk.stripped
            }
        }
        return rows
    }

    /// The row `chunk` moves the cursor to, if it is a cursor move — which
    /// `MockTerminal.moveCursor(toRow:column:)` writes as a chunk of its own.
    private func cursorRow(_ chunk: String) -> Int? {
        let introducer = "\u{1B}["
        guard chunk.hasPrefix(introducer), chunk.hasSuffix("H") else { return nil }
        let fields = chunk.dropFirst(introducer.count).dropLast().split(separator: ";")
        guard fields.count == 2, Int(fields[1]) != nil else { return nil }
        return Int(fields[0])
    }

    /// The screen every write since the terminal was last reset leaves, row by
    /// row (1-based, as the cursor moves count them), escapes stripped: each
    /// cursor move places the text after it, and `ESC[2K` erases the row.
    ///
    /// The stronger oracle, for a frame that changes some rows of the bar and
    /// leaves others alone: a row an earlier frame drew and this one did not
    /// rewrite still shows, as it does on a terminal.
    private func screen(_ terminal: MockTerminal, width: Int = 80, height: Int = 24) -> [Int: String] {
        var grid = Array(repeating: Array(repeating: Character(" "), count: width), count: height + 1)
        var row = 1
        var column = 1
        for chunk in terminal.writtenOutput {
            if let moved = cursorRow(chunk) {
                row = moved
                let fields = chunk.dropFirst(2).dropLast().split(separator: ";")
                column = Int(fields[1]) ?? 1
                continue
            }
            if chunk.contains("\u{1B}[2K"), row <= height {
                grid[row] = Array(repeating: " ", count: width)
            }
            for character in chunk.stripped where row <= height && column <= width {
                grid[row][column - 1] = character
                column += 1
            }
        }
        var rows: [Int: String] = [:]
        for index in 1...height { rows[index] = String(grid[index]) }
        return rows
    }

    /// Whether a row's paint draws anything but spaces.
    private func isInked(_ paint: String?) -> Bool {
        paint?.contains(where: { $0 != " " }) ?? false
    }

    /// A tooltip in the bar moves the bar's top edge, and the screen shows every
    /// row of the bar at its new place — on the way up and on the way down.
    ///
    /// When the bar was a diff region of its own, the diff compared its rows by
    /// index from wherever the bar was written, and only the bar appearing or
    /// disappearing invalidated it. A tooltip grows the bar upwards by a row, and
    /// the top border — the same bytes either side of the move — compared equal
    /// and was skipped. Showing the tooltip left blank the row the content pass had
    /// just erased; hiding it never revisited the row the border returned to, so
    /// the tooltip's text stayed there. The bar is rows of the frame now, diffed by
    /// their place on the screen; this holds it to what the screen shows.
    @Test("A tooltip that moves the bar's top edge repaints every row of the bar, both ways")
    func tooltipMovingTheBarRepaintsIt() {
        let harness = RenderLoopHarness()
        let loop = harness.loop(StatusBarProbeApp())
        let tooltips = harness.tuiContext.tooltipState
        _ = loop.render()
        #expect(loop.windowChrome.rows(.bottom) == 1, "pre-condition: the default bordered bar, `q quit` only")

        // 80x24, `MockTerminal`'s size: the grown bar is rows 21...24.
        tooltips.hovering("Rebuild the index", handlerID: nil, nowNanos: 0)
        _ = loop.render()
        #expect(harness.statusBar.tooltipLines.count == 1, "pre-condition: the tooltip must add a row, or nothing moved")
        let shown = screen(harness.terminal)
        for row in 21...24 {
            #expect(isInked(shown[row]), "row \(row) of the grown bar: \(shown[row].debugDescription)")
        }
        #expect((shown[22] ?? "").contains("Rebuild the index"), "\(shown)")

        tooltips.leaving("Rebuild the index")
        _ = loop.render()
        #expect(harness.statusBar.tooltipLines.isEmpty, "pre-condition: the tooltip must be gone")
        let hidden = screen(harness.terminal)
        #expect(!isInked(hidden[21]), "the row the bar's top edge left: \(hidden[21].debugDescription)")
        for row in 22...24 {
            #expect(isInked(hidden[row]), "row \(row) of the shrunk bar: \(hidden[row].debugDescription)")
        }
        #expect(!(hidden[22] ?? "").contains("Rebuild"), "the tooltip's text is gone: \(hidden)")
    }

    /// A tooltip with no bar of items still draws in the rows it made room for.
    ///
    /// The tooltip row counts with no items to show — the bar that holds it is
    /// reserved before the walk, because its triggers land between frames — so
    /// the page is shortened for it. The loop once built the bar only when it had
    /// items, so the content pass erased those rows and nothing was drawn in them.
    @Test("A tooltip on a bar with no items is drawn in the rows it reserves")
    func tooltipOnAnItemlessBarIsDrawn() {
        let harness = RenderLoopHarness()
        harness.statusBar.showSystemItems = false
        let loop = harness.loop(StatusBarProbeApp())
        _ = loop.render()
        #expect(loop.windowChrome.rows(.bottom) == 0, "pre-condition: no items, no bar")

        // A bordered bar round one tooltip row: rows 22...24 of 24.
        harness.tuiContext.tooltipState.hovering("Copy to clipboard", handlerID: nil, nowNanos: 0)
        harness.terminal.reset()
        _ = loop.render()
        #expect(harness.statusBar.tooltipLines.count == 1, "pre-condition: the tooltip must take its rows")
        let drawn = paints(harness.terminal)
        for row in 22...24 {
            #expect(isInked(drawn[row]), "row \(row) of the tooltip's bar: \(drawn[row].debugDescription)")
        }
        let tooltipRow = drawn[23] ?? ""
        #expect(tooltipRow.contains("Copy to clipboard"), "\(drawn)")
    }

    /// A bar whose only items are declared by the page is drawn on the screen.
    ///
    /// Its height used to be read BEFORE the walk, when the page's declarations
    /// had been cleared and not yet made again. With the system items hidden
    /// nothing else counted, so the page was laid out with no bar, and the bar
    /// the walk then declared was written one row past the bottom of the screen,
    /// where no terminal shows it — the circularity an opt-in bottom bar exposes
    /// (the A28 design study, §2.3). The window's chrome reserves the rows the
    /// walk declared, from the first frame's measuring walk on.
    @Test("A bar of page-declared items alone is drawn on the screen")
    func declaredItemsAloneAreDrawn() {
        let harness = RenderLoopHarness()
        harness.statusBar.showSystemItems = false
        let loop = harness.loop(DeclaredItemProbeApp())
        _ = loop.render()
        let drawn = paints(harness.terminal)
        // A bordered bar round one item row: rows 22...24 of 24.
        for row in 22...24 {
            #expect(isInked(drawn[row]), "row \(row) of the bar: \(drawn[row].debugDescription)")
        }
        #expect((drawn[23] ?? "").contains("save"), "\(drawn)")
        #expect(drawn[25] == nil, "nothing is written past the screen")
    }

    /// An app that sets its status bar's highlight to cyan gets cyan.
    ///
    /// The loop used to read `.cyan` as "not set" and paint the palette's accent in
    /// its place, which is how it themed the bar while `.cyan` was the default. The
    /// default is `nil` now, so cyan is only ever a colour an app chose.
    @Test("A highlight the app sets to cyan is drawn cyan, not replaced by the accent")
    func explicitCyanHighlightIsKept() {
        let harness = RenderLoopHarness()
        harness.statusBar.highlightColor = .ansi(.cyan)
        let loop = harness.loop(StatusBarItemsProbeApp())
        ColorDepth.withCurrent(.truecolor) { _ = loop.render() }
        let written = harness.terminal.writtenOutput.joined()
        // Bold comes before the foreground in `ANSIRenderer`'s codes.
        #expect(written.contains("\u{1B}[1;36m"), "\(written.debugDescription)")
    }
}
