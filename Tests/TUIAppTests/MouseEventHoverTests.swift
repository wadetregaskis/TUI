//  🖥️ TUI — A Terminal UI framework for Swift
//  MouseEventHoverTests.swift
//
//  `.onMouseEvent` hears the pointer come and go as `.onHover` does, beside
//  what is inside it, whatever it returns. Until 2026-11-20 its region was the
//  control under the pointer, so a hover handler or a help inside it heard
//  nothing, though the closure returned `false` for every event (tuidisk's
//  TUI-FEEDBACK.md, milestone 2 item 6).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIApp
@testable import TUIFoundation
import TUITesting

@MainActor
@Suite("onMouseEvent leaves the hover to what is inside it")
struct MouseEventHoverTests {
    /// What reached the handlers under test, in order.
    final class Heard {
        var events: [String] = []
    }

    @Test("onContinuousHover inside an onMouseEvent that claims nothing hears the pointer")
    func hoverInsideDecliningHandler() {
        let heard = Heard()
        let app = TestApp(width: 40, height: 12) {
            Rectangle().fill(.blue)
                .onContinuousHover { _ in heard.events.append("hover") }
                .onMouseEvent { event in
                    if event.phase == .entered { heard.events.append("raw") }
                    return false
                }
        }
        app.hover(at: CellPoint(x: 12, y: 6))
        #expect(heard.events.contains("raw"), "the raw handler hears the pointer come in: \(heard.events)")
        #expect(heard.events.contains("hover"), "and so does the hover inside it: \(heard.events)")
    }

    @Test("The raw handler hears the pointer leave its view")
    func rawHandlerHearsExit() {
        let heard = Heard()
        let app = TestApp(width: 40, height: 12) {
            VStack(spacing: 0) {
                Text("watched")
                    .onMouseEvent { event in
                        switch event.phase {
                        case .entered: heard.events.append("entered")
                        case .exited: heard.events.append("exited")
                        default: break
                        }
                        return false
                    }
                Spacer()
            }
            // Asks the terminal for the pointer's moves, which a raw handler
            // alone does not.
            .onHover { _ in }
        }
        try? app.hover(over: "watched")
        app.hover(at: CellPoint(x: 20, y: 10))
        #expect(heard.events == ["entered", "exited"])
    }

    @Test("A help inside .onScrollWheel shows under the pointer")
    func helpInsideScrollWheel() {
        let app = TestApp(width: 40, height: 12) {
            Rectangle().fill(.blue)
                .help("TIP")
                .onScrollWheel { _ in true }
        }
        app.hover(at: CellPoint(x: 12, y: 6))
        app.advance(by: .seconds(3))
        #expect(app.screen.contains("TIP"))
    }

    @Test("A press the raw handler declines still reaches the tap inside it")
    func declinedPressReachesTap() {
        let heard = Heard()
        let app = TestApp(width: 40, height: 12) {
            Rectangle().fill(.blue)
                .onTapGesture { heard.events.append("tap") }
                .onMouseEvent { _ in false }
        }
        app.click(at: CellPoint(x: 12, y: 6))
        app.advance(by: .seconds(1))
        #expect(heard.events == ["tap"])
    }
}
