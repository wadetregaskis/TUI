//  🖥️ TUIkit — Terminal UI Kit for Swift
//  MenuPointerShapeTests.swift
//
//  Created by Wade Tregaskis
//  License: MIT

import Testing

@testable import TUIkitApp
@testable import TUIkitFoundation
import TUIkitMenus
@testable import TUIkitTestSupport

private struct MenuApp: App {
    var body: some Scene {
        WindowGroup {
            Menu("Actions") {
                Button("First") {}
                Button("Second") {}
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// A `Menu`'s trigger is a button, and is given its hand where TUIkit's
/// controls set their own shapes; its rows are a list, and are not
/// (decisions O12, B-O12-6).
@MainActor
@Suite("Menus' pointer shapes")
struct MenuPointerShapeTests {
    @Test("A menu's trigger is given a hand, and its rows are not")
    func menuRowsKeepThePointer() throws {
        let app = HeadlessApp(MenuApp(), width: 40, height: 12)
        app.services.terminalFeatures = TerminalFeatures(pointerShapes: true, controlPointerShapes: true)
        var now: Int64 = 0
        func step() {
            now += 16_666_667
            app.frame(atNanos: now)
        }
        func position(of text: String) -> (x: Int, y: Int)? {
            for (y, line) in app.screen.map(\.stripped).enumerated() {
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
        let trigger = try #require(position(of: "Actions"), "the Menu was not drawn: \(app.screen)")
        #expect(shape(atX: trigger.x, y: trigger.y) == .link)
        app.send(MouseEvent(button: .left, phase: .pressed, x: trigger.x, y: trigger.y))
        app.send(MouseEvent(button: .left, phase: .released, x: trigger.x, y: trigger.y))
        step()
        step()
        let row = try #require(position(of: "Second"), "the Menu did not open: \(app.screen)")
        #expect(shape(atX: row.x, y: row.y) == nil)
    }
}
