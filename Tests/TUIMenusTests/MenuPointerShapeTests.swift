//  🖥️ TUI — A Terminal UI framework for Swift
//  MenuPointerShapeTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIApp
@testable import TUIAppTestSupport
@testable import TUIFoundation
import TUIMenus
import TUITesting
@testable import TUITestSupport

private struct MenuApp: App {
    var body: some Scene {
        WindowGroup {
            Menu("Actions") {
                Button("First") {}
                Button("Second") {}
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .pointingHandCursor(over: .everythingClickable)
        }
    }
}

/// A `Menu`'s trigger is a button, and is given its hand where TUI's
/// controls set their own shapes and the app asks for a hand over every
/// control (`pointingHandCursor(over: .everythingClickable)`, decisions A-O12-1); its rows are a
/// list, and are not, even then (decisions O12, B-O12-6).
@MainActor
@Suite("Menus' pointer shapes")
struct MenuPointerShapeTests {
    @Test("A menu's trigger is given a hand, and its rows are not")
    func menuRowsKeepThePointer() throws {
        let app = TestApp(MenuApp(), width: 40, height: 12)
        app.services.terminalFeatures = TerminalFeatures(pointerShapes: true, controlPointerShapes: true)
        var now: Int64 = 0
        func step() {
            now += 16_666_667
            app.frame(atNanos: now)
        }
        func position(of text: String) -> (x: Int, y: Int)? {
            for (y, line) in app.screen.lines.enumerated() {
                guard let range = line.range(of: text) else { continue }
                return (line.distance(from: line.startIndex, to: range.lowerBound), y)
            }
            return nil
        }
        func shape(atX x: Int, y: Int) -> PointerShape? {
            app.send(MouseEvent(button: .none, phase: .moved, x: x, y: y))
            return app.services.mouseEventDispatcher.pointerShapeUnderPointer()
        }
        step()
        let trigger = try #require(position(of: "Actions"), "the Menu was not drawn: \(app.screen.styledLines)")
        #expect(shape(atX: trigger.x, y: trigger.y) == .link)
        app.send(MouseEvent(button: .left, phase: .pressed, x: trigger.x, y: trigger.y))
        app.send(MouseEvent(button: .left, phase: .released, x: trigger.x, y: trigger.y))
        step()
        step()
        let row = try #require(position(of: "Second"), "the Menu did not open: \(app.screen.styledLines)")
        #expect(shape(atX: row.x, y: row.y) == nil)
    }
}
