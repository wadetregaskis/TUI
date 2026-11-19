//  🖥️ TUI — A Terminal UI framework for Swift
//  MenuKeyboardOpenRestingPointerTests.swift
//
//  A menu the keyboard opens under a pointer resting where it last moved to
//  keeps the row the keyboard lit until the pointer moves, as a macOS menu
//  opened from the keyboard does (lead decision, 2026-11-18; B-MENUS-4). It
//  took the row under the pointer as the hover's reconcile entered it, after
//  the frame that drew the first row lit, and Return ran a row the screen had
//  not lit (the Stress menus session, steps 419 and 803).
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
private final class RanLog {
    var ran: [String] = []
}

private struct ExportApp: App {
    let log: RanLog?

    init() { log = nil }

    init(_ log: RanLog) { self.log = log }

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
@Suite("A menu the keyboard opens under a resting pointer")
struct MenuKeyboardOpenRestingPointerTests {
    /// The app with its menu opened once from the keyboard and closed, the
    /// pointer then moved to where the menu draws "Export HTML" — over the
    /// page while it is closed — and the menu opened again from the keyboard,
    /// under it.
    private func openedUnderRestingPointer(_ log: RanLog) throws -> (app: TestApp, html: CellPoint) {
        let app = TestApp(ExportApp(log), width: 60, height: 16)
        if app.screen.location(of: "Export PDF") == nil { app.press(.enter) }
        if app.screen.location(of: "Export PDF") == nil {
            app.press(.tab)
            app.press(.enter)
        }
        let html = try #require(app.screen.location(of: "Export HTML"), "Return opens the menu: \(app.screen)")
        app.press(.escape)
        #expect(app.screen.location(of: "Export HTML") == nil, "Escape closes it: \(app.screen)")
        let rest = CellPoint(x: html.x + 2, y: html.y)
        app.mouse(MouseEvent(button: .none, phase: .moved, x: rest.x, y: rest.y))
        app.press(.enter)
        #expect(app.screen.location(of: "Export HTML") == html, "it opens where it did: \(app.screen)")
        return (app, rest)
    }

    @Test("It keeps its first row lit, and Return runs that row")
    func keepsTheKeyboardsRow() throws {
        let log = RanLog()
        let (app, _) = try openedUnderRestingPointer(log)
        app.press(.enter)
        #expect(log.ran == ["PDF"], "the resting pointer took the row it was over: \(log.ran)")
    }

    @Test("A move within the row under the pointer lights it, and Return runs it")
    func aMoveTakesTheRow() throws {
        let log = RanLog()
        let (app, rest) = try openedUnderRestingPointer(log)
        app.mouse(MouseEvent(button: .none, phase: .moved, x: rest.x + 1, y: rest.y))
        app.press(.enter)
        #expect(log.ran == ["HTML"], "the pointer's move did not take the row under it: \(log.ran)")
    }

    @Test("A move onto another row lights that row")
    func aMoveToAnotherRow() throws {
        let log = RanLog()
        let (app, rest) = try openedUnderRestingPointer(log)
        app.mouse(MouseEvent(button: .none, phase: .moved, x: rest.x, y: rest.y + 1))
        app.press(.enter)
        #expect(log.ran == ["Text"], "the pointer's move did not take the row it moved to: \(log.ran)")
    }

    @Test("A report of the pointer at the cell it rests on is not a move")
    func aReportInPlaceIsNotAMove() throws {
        let log = RanLog()
        let (app, rest) = try openedUnderRestingPointer(log)
        app.mouse(MouseEvent(button: .none, phase: .moved, x: rest.x, y: rest.y))
        app.press(.enter)
        #expect(log.ran == ["PDF"], "a report in place took the row: \(log.ran)")
    }

    @Test("A menu the pointer opens under the resting pointer still follows it")
    func aPointerOpenedMenuFollows() throws {
        let log = RanLog()
        let (app, rest) = try openedUnderRestingPointer(log)
        app.press(.escape)
        // Back over the trigger, then the click that opens it; the pointer's
        // move onto the row then lights it, as before.
        let trigger = try #require(app.screen.location(of: "Export ▾"))
        let triggerCell = CellPoint(x: trigger.x + 2, y: trigger.y)
        app.mouse(MouseEvent(button: .none, phase: .moved, x: triggerCell.x, y: triggerCell.y))
        app.click(at: triggerCell)
        app.mouse(MouseEvent(button: .none, phase: .moved, x: rest.x, y: rest.y))
        app.press(.enter)
        #expect(log.ran == ["HTML"], "a pointer-opened menu did not follow the pointer: \(log.ran)")
    }
}
