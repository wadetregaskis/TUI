//  🖥️ TUI — A Terminal UI framework for Swift
//  SheetKeyboardResizeTests.swift
//
//  A sheet resized and moved from the keyboard: its Resize and Move stops
//  after its content in the Tab order, what their keys do, the grips and the
//  breathing border that say which has the focus, and the status bar's hint.
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUICore
@testable import TUIFoundation
@testable import TUIPresentation
@testable import TUITestSupport

/// A page under a sheet of two buttons, or of one line of text — too short to
/// resize.
@MainActor
private struct SheetPage: View {
    var oneRow = false
    var persisted: (width: Int?, height: Int?)?
    var onResize: ((Int?, Int?) -> Void)?
    var onResetSize: (() -> Void)?

    var body: some View {
        Text("PAGE").sheet(isPresented: .constant(true)) { content }
    }

    @ViewBuilder private var content: some View {
        if oneRow {
            Button("Only") {}.focusID("only")
        } else if let persisted {
            dialog.presentationPersistedSize(
                width: persisted.width, height: persisted.height, onResize: onResize, onResetSize: onResetSize)
        } else {
            dialog
        }
    }

    private var dialog: some View {
        Dialog(title: "Sheet") {
            Button("First") {}.focusID("first")
            Button("Second") {}.focusID("second")
        }
    }
}

@MainActor
@Suite("Sheet keyboard resizing and moving")
struct SheetKeyboardResizeTests {
    private static let width = 60
    private static let height = 20

    private func harness() -> InputChainHarness {
        InputChainHarness(width: Self.width, height: Self.height) { environment in
            environment.terminalWidth = Self.width
            environment.overlayContentHeight = Self.height
        }
    }

    /// The sheet's layer after a frame of `view`.
    @discardableResult
    private func sheet(_ harness: InputChainHarness, _ view: SheetPage = SheetPage()) -> OverlayLayer? {
        harness.frame(view).overlays.first { $0.level == .modal }
    }

    private func focused(_ harness: InputChainHarness) -> String {
        let id = harness.focusManager.currentFocusedID ?? "nil"
        if id.hasPrefix("sheet-resize") { return "resize" }
        if id.hasPrefix("sheet-move") { return "move" }
        return id
    }

    /// Tabs to the stop `role` names, with a frame after each key.
    private func tab(to role: String, _ harness: InputChainHarness, _ view: SheetPage = SheetPage()) {
        sheet(harness, view)
        sheet(harness, view)
        for _ in 0..<6 where focused(harness) != role {
            harness.press(KeyEvent(key: .tab))
            sheet(harness, view)
        }
        #expect(focused(harness) == role)
    }

    /// Presses `key` on the focused stop and returns the sheet drawn after it.
    private func press(
        _ key: Key, shift: Bool = false, _ harness: InputChainHarness, _ view: SheetPage = SheetPage()
    ) throws -> OverlayLayer {
        #expect(harness.press(KeyEvent(key: key, shift: shift)), "the stop takes \(key)")
        return try #require(sheet(harness, view))
    }

    // MARK: - The ring

    @Test("After the sheet's last control come Resize, then Move, then round; Shift-Tab the reverse")
    func ringOrder() {
        let harness = harness()
        sheet(harness)
        sheet(harness)
        #expect(focused(harness) == "first", "the content takes the opening focus")
        var forward: [String] = []
        for _ in 0..<4 {
            harness.press(KeyEvent(key: .tab))
            sheet(harness)
            forward.append(focused(harness))
        }
        #expect(forward == ["second", "resize", "move", "first"])
        var backward: [String] = []
        for _ in 0..<4 {
            harness.press(KeyEvent(key: .tab, shift: true))
            sheet(harness)
            backward.append(focused(harness))
        }
        #expect(backward == ["move", "resize", "second", "first"])
    }

    @Test("A sheet too short to resize has only the Move stop")
    func noResizeOnlyMove() {
        let harness = harness()
        let view = SheetPage(oneRow: true)
        sheet(harness, view)
        sheet(harness, view)
        var stops: [String] = []
        for _ in 0..<3 {
            harness.press(KeyEvent(key: .tab))
            sheet(harness, view)
            stops.append(focused(harness))
        }
        #expect(stops == ["move", "only", "move"])
    }

    @Test("An alert has neither stop, and no grips")
    func alertHasNeither() throws {
        let harness = harness()
        func alert() -> some View {
            Text("PAGE").alert("Warning", isPresented: .constant(true)) {
                Button("OK") {}
                Button("Cancel", role: .cancel) {}
            }
        }
        harness.frame(alert())
        let layer = try #require(harness.frame(alert()).overlays.first { $0.level == .alert })
        for _ in 0..<4 {
            harness.press(KeyEvent(key: .tab))
            harness.frame(alert())
            #expect(!["resize", "move"].contains(focused(harness)))
        }
        let rows = layer.content.lines.map(\.stripped)
        #expect(!rows.contains { $0.contains("═") || $0.contains("║") || $0.contains("╝") }, "\(rows)")
    }

    // MARK: - Resize

    @Test("Arrows on Resize resize as a drag does: about the centre while centred")
    func resizeCentred() throws {
        let harness = harness()
        tab(to: "resize", harness)
        let start = try #require(sheet(harness))
        let (width, height) = (start.content.width, start.content.height)
        var layer = try press(.right, harness)
        #expect(layer.content.width == width + 2 && layer.offsetX == 0, "both sides out by one")
        layer = try press(.down, harness)
        #expect(layer.content.height == height + 2 && layer.offsetY == 0)
        layer = try press(.right, shift: true, harness)
        #expect(layer.content.width == width + 12, "Shift steps five")
        layer = try press(.left, harness)
        #expect(layer.content.width == width + 10)
        layer = try press(.up, harness)
        #expect(layer.content.height == height)
        layer = try press(.home, harness)
        #expect(layer.content.width == width && layer.content.height == height, "Home: its own size")
        #expect(focused(harness) == "resize", "the focus stays on the stop")
    }

    @Test("Moved off centre, a resize keeps the sheet's left edge where it is")
    func resizeAnchoredOffCentre() throws {
        let harness = harness()
        tab(to: "move", harness)
        var layer = try press(.right, shift: true, harness)
        #expect(layer.offsetX == 5)
        func left(_ layer: OverlayLayer) -> Int { (Self.width - layer.content.width) / 2 + layer.offsetX }
        let edge = left(layer)
        let width = layer.content.width
        harness.press(KeyEvent(key: .tab, shift: true))
        sheet(harness)
        #expect(focused(harness) == "resize")
        layer = try press(.right, harness)
        #expect(layer.content.width == width + 1, "one side out by one")
        #expect(left(layer) == edge)
    }

    @Test("A step reports the axis it set, and the other only where the user set it; Home says reset")
    func resizeReportsAndResets() throws {
        let harness = harness()
        var reported: [String] = []
        var resets = 0
        let view = SheetPage(
            persisted: (nil, nil), onResize: { reported.append("\($0.map(String.init) ?? "nil")×\($1.map(String.init) ?? "nil")") },
            onResetSize: { resets += 1 })
        tab(to: "resize", harness, view)
        let width = try #require(sheet(harness, view)).content.width
        _ = try press(.right, harness, view)
        #expect(reported == ["\(width + 2)×nil"], "the height was never set: not saved")
        _ = try press(.home, harness, view)
        #expect(resets == 1)
    }

    @Test("Home puts a sheet opened at a persisted size back at its own")
    func homeLeavesThePersistedSize() throws {
        let harness = harness()
        let natural = try #require(sheet(harness)).content.width
        let harness2 = self.harness()
        let view = SheetPage(persisted: (natural + 10, nil))
        tab(to: "resize", harness2, view)
        #expect(try #require(sheet(harness2, view)).content.width == natural + 10, "opened at the persisted size")
        let layer = try press(.home, harness2, view)
        #expect(layer.content.width == natural, "the persisted size is where it opens, not where Home goes")
    }

    // MARK: - Move

    @Test("Arrows on Move move the sheet, kept on screen; Home centres it")
    func moveAndCentre() throws {
        let harness = harness()
        tab(to: "move", harness)
        var layer = try press(.right, harness)
        #expect(layer.offsetX == 1 && layer.offsetY == 0)
        layer = try press(.down, shift: true, harness)
        #expect(layer.offsetY == 5)
        for _ in 0..<20 { harness.press(KeyEvent(key: .right, shift: true)) }
        layer = try #require(sheet(harness))
        let span = Self.width - layer.content.width
        #expect(layer.offsetX == span - span / 2, "its right edge at the screen's")
        layer = try press(.left, harness)
        #expect(layer.offsetX == span - span / 2 - 1, "a step back from the edge moves at once")
        layer = try press(.home, harness)
        #expect(layer.offsetX == 0 && layer.offsetY == 0)
    }

    // MARK: - Drawn

    /// The cells breathing in `layer`: those its animated runs cover.
    private func breathing(_ layer: OverlayLayer) -> Set<[Int]> {
        var cells: Set<[Int]> = []
        for run in layer.content.animatedCells {
            for x in run.offsetX..<(run.offsetX + run.width) { cells.insert([x, run.offsetY]) }
        }
        return cells
    }

    @Test("A resizable sheet draws the resizable views' grips; the focused stop breathes")
    func gripsAndBreath() throws {
        let harness = harness()
        let rest = try #require(sheet(harness))
        let rows = rest.content.lines.map(\.stripped)
        let (width, height) = (rest.content.width, rest.content.height)
        let bottom = try #require(rows.last)
        #expect(bottom.hasSuffix("╝"), "the corner: \(rows)")
        #expect(bottom.contains("═══════"), "the bottom edge's handle: \(rows)")
        #expect(rows[height / 2].hasSuffix("║"), "the right edge's handle: \(rows)")
        let span = try #require(BorderGrip.centredSpan(in: width, size: BorderGrip.Size.horizontal))
        let grip = [span.lowerBound, height - 1]
        // The focused button inside breathes; the edges do not.
        let resting = breathing(rest)
        #expect(!resting.contains(grip) && !resting.contains([width - 1, height - 1]) && !resting.contains([0, 0]))
        tab(to: "resize", harness)
        let resizing = breathing(try #require(sheet(harness)))
        #expect(resizing.contains(grip) && resizing.contains([width - 1, height - 1]))
        #expect(!resizing.contains([0, 0]), "the border does not breathe for Resize")

        harness.press(KeyEvent(key: .tab))
        let moving = breathing(try #require(sheet(harness)))
        #expect(focused(harness) == "move")
        #expect(moving.contains([0, 0]) && moving.contains([0, height / 2]) && moving.contains([1, height - 1]))
        #expect(!moving.contains(grip) && !moving.contains([width - 1, height - 1]), "but not its grips")
    }

    @Test("The status bar names the focused stop's keys")
    func statusBarHint() {
        let harness = harness()
        let strings = LocalizationService.shared
        func labels() -> [String: String] {
            Dictionary(
                harness.statusBar.currentItems.map { ($0.shortcut, $0.label) }, uniquingKeysWith: { first, _ in first })
        }
        sheet(harness)
        sheet(harness)
        #expect(labels()[Shortcut.arrowsAll] == nil)
        tab(to: "resize", harness)
        #expect(labels()[Shortcut.arrowsAll] == strings.string(for: LocalizationKey.StatusBar.resize))
        #expect(labels()[Shortcut.home] == strings.string(for: LocalizationKey.StatusBar.resetSize))
        tab(to: "move", harness)
        #expect(labels()[Shortcut.arrowsAll] == strings.string(for: LocalizationKey.StatusBar.move))
        #expect(labels()[Shortcut.home] == strings.string(for: LocalizationKey.StatusBar.centre))
    }
}
