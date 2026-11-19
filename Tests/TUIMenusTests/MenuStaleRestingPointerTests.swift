//  🖥️ TUI — A Terminal UI framework for Swift
//  MenuStaleRestingPointerTests.swift
//
//  Where the pointer rests is the cell of the last report of its motion — a
//  move, or a drag — and a click is not counted as one. But a click reported
//  at another cell says the pointer has left the one it rested on, however it
//  got there unreported. Kept, that stale cell was where a menu opening under
//  it counted the pointer as resting: a menu dragged from, then clicked open
//  again from its trigger, lit the row the drag had ended on as it opened —
//  undrawn, so Down from "nothing" went to the second row and Return ran it.
//  Found by the Stress `menus` session at its step 181 (the default 400 steps;
//  the selfcheck's 150 never reached it, which is why it passed there and was
//  taken for a release-only failure).
//
//  Created by Wade Tregaskis
//  License: MIT

import Observation
import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUIMenus
import TUITesting
@testable import TUITestSupport

@Observable
@MainActor
private final class ExportLog {
    var ran: [String] = []
}

private struct ExportApp: App {
    let log: ExportLog?

    init() { log = nil }

    init(_ log: ExportLog) { self.log = log }

    var body: some Scene {
        WindowGroup {
            if let log {
                VStack(alignment: .leading, spacing: 0) {
                    Menu("Export") {
                        Button("Export PDF") { log.ran.append("PDF") }
                        Button("Export HTML") { log.ran.append("HTML") }
                        Button("Export Text") { log.ran.append("Text") }
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .mouseSupport(.full)
    }
}

@MainActor
@Suite("A click elsewhere forgets where the pointer rested")
struct MenuStaleRestingPointerTests {
    @Test("A menu clicked open again does not light the row an earlier drag ended on, so Down enters at the top")
    func reopenedMenuEntersAtTheTop() throws {
        let log = ExportLog()
        let app = TestApp(ExportApp(log), width: 60, height: 16)
        let trigger = try #require(app.screen.location(of: "Export ▾"))
        let triggerCell = CellPoint(x: trigger.x + 2, y: trigger.y)
        // Opened by a press dragged onto its first row and let go there, as a
        // pointer opens and chooses from a menu in one gesture.
        app.mouse(MouseEvent(button: .left, phase: .pressed, x: triggerCell.x, y: triggerCell.y))
        let pdf = try #require(app.screen.location(of: "Export PDF"), "the press opens the menu: \(app.screen)")
        app.mouse(MouseEvent(button: .left, phase: .dragged, x: pdf.x + 1, y: pdf.y))
        app.mouse(MouseEvent(button: .left, phase: .released, x: pdf.x + 1, y: pdf.y))
        #expect(log.ran == ["PDF"], "precondition: the drag chose its row")

        // Clicked open again from its trigger, with no motion reported on the
        // way back: the pointer is at the trigger, not on the row it left.
        app.click(at: triggerCell)
        #expect(app.screen.location(of: "Export PDF") != nil, "the click opens it again: \(app.screen)")
        #expect(
            app.services.mouseEventDispatcher.restingPointer == nil,
            "a click at another cell still has the pointer resting where the drag left it")
        app.press(.down)
        app.press(.enter)
        #expect(log.ran == ["PDF", "PDF"], "Down entered a pointer-opened menu below its top: \(log.ran)")
    }

    @Test("A click on the cell the pointer last moved to keeps it resting there")
    func clickInPlaceKeepsTheRestingCell() {
        let app = TestApp(ExportApp(ExportLog()), width: 60, height: 16)
        app.mouse(MouseEvent(button: .none, phase: .moved, x: 30, y: 8))
        app.click(at: CellPoint(x: 30, y: 8))
        let resting = app.services.mouseEventDispatcher.restingPointer
        #expect(resting?.x == 30 && resting?.y == 8, "a click where the pointer rests is no news: \(String(describing: resting))")
    }
}
