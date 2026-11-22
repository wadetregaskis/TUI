//  🖥️ TUI — A Terminal UI framework for Swift
//  OffWindowRowRestrictionTests.swift
//
//  `.deleteDisabled()`, `.moveDisabled()` and `.selectionDisabled()` on rows
//  OUTSIDE the drawn window. The rows report their refusals as they render,
//  and the list used to rebuild what it knew from the rows of each frame
//  alone: with the cursor row wheeled out of sight, Delete removed a locked
//  row and Ctrl+Down moved a pinned one, and Select All and a Shift span
//  selected disabled rows that were off screen (hunt findings LISTS-1 and
//  LISTS-2). Owner ruling O-04 (2026-11-21): the reports are kept across
//  frames by row id; Select All and a span build the rows no frame has drawn,
//  on the key; Delete and the move keys learn the cursor row's and the held
//  rows' refusals before they act.
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

@testable import TUIApp
@testable import TUIFoundation
@testable import TUILists
@testable import TUITestSupport

@MainActor
@Suite("Row restrictions outside the drawn window")
struct OffWindowRowRestrictionTests {

    private struct Row: Identifiable, Equatable {
        let id: Int
        var locked: Bool
    }

    @MainActor
    private final class Fixture {
        var rows: [Row]
        var selection = Set<Int>()
        var deletes: [IndexSet] = []
        var moves: [(IndexSet, Int)] = []
        let tui = TUIContext()
        var env = EnvironmentValues()

        init(count: Int, locked: Set<Int>) {
            rows = (0..<count).map { Row(id: $0, locked: locked.contains($0)) }
            env.focusManager = FocusManager()
            env.applyRuntimeServices(from: tui)
            tui.mouseEventDispatcher.setActiveSupport(.full)
        }

        var handler: ItemListHandler<Int>? {
            env.focusManager?.currentFocused as? ItemListHandler<Int>
        }

        var selectionBinding: Binding<Set<Int>> {
            Binding(get: { self.selection }, set: { self.selection = $0 })
        }

        @discardableResult
        func render(_ view: some View, measuring: Bool = false) -> FrameBuffer {
            tui.stateStorage.beginRenderPass()
            env.focusManager?.beginRenderPass()
            var context = RenderContext(
                availableWidth: 24, availableHeight: 12, environment: env, tuiContext: tui)
            context.isMeasuring = measuring
            let buffer = renderToBuffer(view, context: context)
            env.focusManager?.endRenderPass()
            tui.stateStorage.endRenderPass()
            return buffer
        }

        /// Turns the wheel down `ticks` times and draws the frame that follows.
        func wheel(down ticks: Int, _ view: some View) throws {
            let handler = try #require(handler)
            for _ in 0..<ticks {
                _ = handler.handleWheelEvent(MouseEvent(button: .scrollDown, phase: .scrolled, x: 0, y: 0))
            }
            render(view)
        }
    }

    private func deletableList(_ fixture: Fixture) -> some View {
        List(selection: .constant(Int?.none)) {
            ForEach(fixture.rows) { row in
                Text("row \(row.id)").deleteDisabled(row.locked)
            }
            .onDelete { offsets in
                fixture.deletes.append(offsets)
                fixture.rows.remove(atOffsets: offsets)
            }
        }
        .frame(height: 10)
    }

    private func movableList(_ fixture: Fixture) -> some View {
        List(selection: fixture.selectionBinding) {
            ForEach(fixture.rows) { row in
                Text("row \(row.id)").moveDisabled(row.locked)
            }
            .onMove { source, destination in
                fixture.moves.append((source, destination))
                fixture.rows.move(fromOffsets: source, toOffset: destination)
            }
        }
        .frame(height: 10)
    }

    private func selectableList(_ fixture: Fixture) -> some View {
        List(selection: fixture.selectionBinding) {
            ForEach(fixture.rows) { row in
                Text("row \(row.id)").selectionDisabled(row.locked)
            }
        }
        .frame(height: 10)
    }

    // MARK: - Delete and move (ruling O-04 (c))

    @Test("Delete on a locked cursor row wheeled out of sight deletes nothing")
    func deleteAfterWheel() throws {
        let fixture = Fixture(count: 40, locked: [0])
        let view = deletableList(fixture)
        fixture.render(view)
        let handler = try #require(fixture.handler)
        #expect(handler.focusedIndex == 0)
        // Two pages down: the wheel moves the rows, never the cursor.
        try fixture.wheel(down: 6, view)
        #expect(handler.drawnOffset > 0, "row 0 is out of the window (offset \(handler.drawnOffset))")
        #expect(handler.focusedIndex == 0)

        #expect(handler.handleKeyEvent(KeyEvent(key: .delete)) == false, "the key falls through")
        #expect(fixture.deletes.isEmpty, "\(fixture.deletes)")
        #expect(fixture.rows.first?.id == 0, "row 0 remains")
    }

    @Test("Ctrl+Down on a pinned cursor row wheeled out of sight moves nothing")
    func moveAfterWheel() throws {
        let fixture = Fixture(count: 40, locked: [0])
        let view = movableList(fixture)
        fixture.render(view)
        let handler = try #require(fixture.handler)
        try fixture.wheel(down: 6, view)
        #expect(handler.drawnOffset > 0, "row 0 is out of the window (offset \(handler.drawnOffset))")

        // The chord itself is refused; the key then goes on to the cursor
        // keys, as it does on a pinned row on screen.
        #expect(handler.nudgeFocusedRow(by: 1) == false, "the move chord is refused")
        _ = handler.handleKeyEvent(KeyEvent(key: .down, ctrl: true))
        #expect(fixture.moves.isEmpty, "\(fixture.moves.map { (Array($0.0), $0.1) })")
        #expect(fixture.rows.first?.id == 0, "row 0 stayed where it was")
    }

    @Test("A grab of a selection leaves behind a pinned selected row that is off screen")
    func heldSelectionLeavesPinnedRow() throws {
        let fixture = Fixture(count: 40, locked: [0])
        fixture.selection = [0, 20]
        let view = movableList(fixture)
        fixture.render(view)
        let handler = try #require(fixture.handler)
        try fixture.wheel(down: 6, view)
        #expect(handler.drawnOffset > 0, "row 0 is out of the window (offset \(handler.drawnOffset))")

        handler.beginReorder(grabbing: 20)
        #expect(handler.reorder?.held == IndexSet(integer: 20), "\(String(describing: handler.reorder?.held))")
    }

    // MARK: - Select All and spans (ruling O-04 (b))

    @Test("Ctrl+A leaves out a disabled row no frame has drawn")
    func selectAllLeavesNeverDrawnRowOut() throws {
        let fixture = Fixture(count: 100, locked: [50])
        fixture.render(selectableList(fixture))
        let handler = try #require(fixture.handler)
        #expect(!handler.selectionDisabledRows.contains(50), "row 50 has not been drawn")

        #expect(handler.handleKeyEvent(KeyEvent(key: .character("a"), ctrl: true)))
        #expect(fixture.selection.count == 99, "\(fixture.selection.count)")
        #expect(!fixture.selection.contains(50))
    }

    @Test("Shift+End leaves out a disabled row no frame has drawn")
    func shiftEndLeavesNeverDrawnRowOut() throws {
        let fixture = Fixture(count: 100, locked: [50])
        fixture.render(selectableList(fixture))
        let handler = try #require(fixture.handler)

        #expect(handler.handleKeyEvent(KeyEvent(key: .end, shift: true)))
        #expect(handler.focusedIndex == 99)
        #expect(fixture.selection.count == 99, "\(fixture.selection.count)")
        #expect(!fixture.selection.contains(50))
    }

    // MARK: - Reports kept across frames by row id

    @Test("A disabled row drawn once is still known after it is scrolled away")
    func reportOutlivesTheWindow() throws {
        let fixture = Fixture(count: 100, locked: [3])
        let view = selectableList(fixture)
        fixture.render(view)
        let handler = try #require(fixture.handler)
        #expect(handler.selectionDisabledRows == [3])
        try fixture.wheel(down: 10, view)
        #expect(handler.drawnOffset > 3, "row 3 is out of the window (offset \(handler.drawnOffset))")
        #expect(handler.selectionDisabledRows == [3], "\(handler.selectionDisabledRows.sorted())")
    }

    @Test("A kept report follows its row's id when the rows above it go")
    func reportFollowsTheRowID() throws {
        let fixture = Fixture(count: 100, locked: [3])
        let view = { selectableList(fixture) }
        fixture.render(view())
        let handler = try #require(fixture.handler)
        try fixture.wheel(down: 10, view())
        // The first two rows leave the data: the locked row is now list row 1.
        fixture.rows.removeFirst(2)
        fixture.render(view())
        #expect(handler.selectionDisabledRows == [1], "\(handler.selectionDisabledRows.sorted())")
        // …and once it leaves the data, nothing names it.
        fixture.rows.remove(at: 1)
        fixture.render(view())
        #expect(handler.selectionDisabledRows.isEmpty, "\(handler.selectionDisabledRows.sorted())")
    }

    @Test("A row that draws without reporting is forgotten")
    func unlockedRowIsForgotten() throws {
        let fixture = Fixture(count: 20, locked: [3])
        fixture.render(selectableList(fixture))
        let handler = try #require(fixture.handler)
        #expect(handler.selectionDisabledRows == [3])
        fixture.rows[3].locked = false
        fixture.render(selectableList(fixture))
        #expect(handler.selectionDisabledRows.isEmpty, "\(handler.selectionDisabledRows.sorted())")
    }

    @Test("A measuring render does not empty what the drawn rows reported")
    func measuringRenderKeepsReports() throws {
        let fixture = Fixture(count: 5, locked: [1])
        fixture.render(deletableList(fixture))
        let handler = try #require(fixture.handler)
        #expect(handler.deleteDisabledRows == [1])
        fixture.render(deletableList(fixture), measuring: true)
        #expect(handler.deleteDisabledRows == [1], "\(handler.deleteDisabledRows.sorted())")
    }
}
