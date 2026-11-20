//  🖥️ TUI — A Terminal UI framework for Swift
//  FocusableMouseTests.swift
//
//  `.focusable()` (its `.edit` interaction: a click focuses the view) leaves
//  the pointer to what is inside it, as SwiftUI's does on macOS: a tap gesture
//  on a focusable view runs, and the click focuses the view as well; the
//  pointer's moves reach the hover handlers and the help inside it. Until
//  2026-11-20 the modifier put a region in front of its content that took
//  every left press and the hover, so none of them heard anything (tuidisk's
//  TUI-FEEDBACK.md, milestone 2 item 5).
//
//  Created by Wade Tregaskis
//  License: MIT

import Foundation
import Testing

import TUIApp
@testable import TUIFoundation
import TUITesting

@MainActor
@Suite("A focusable view's content keeps the pointer")
struct FocusableMouseTests {
    /// What reached the handlers under test, in order.
    final class Heard {
        var events: [String] = []
    }

    @Test("A tap gesture inside .focusable() runs, and the click focuses the view")
    func tapInside() {
        let heard = Heard()
        let app = TestApp(width: 40, height: 12) {
            VStack {
                Button("first") {}
                Rectangle().fill(.blue)
                    .onTapGesture { heard.events.append("tap") }
                    .focusable()
            }
        }
        #expect(app.focusedID?.hasPrefix("button") == true, "the button starts with the focus")
        app.click(at: CellPoint(x: 20, y: 8))
        app.advance(by: .seconds(1))
        #expect(heard.events == ["tap"])
        #expect(app.focusedID?.hasPrefix("focusable") == true, "the click focused the view")
    }

    @Test("A tap gesture outside .focusable() runs, and the click focuses the view")
    func tapOutside() {
        let heard = Heard()
        let app = TestApp(width: 40, height: 12) {
            VStack {
                Button("first") {}
                Rectangle().fill(.blue)
                    .focusable()
                    .onTapGesture { heard.events.append("tap") }
            }
        }
        app.click(at: CellPoint(x: 20, y: 8))
        app.advance(by: .seconds(1))
        #expect(heard.events == ["tap"])
        #expect(app.focusedID?.hasPrefix("focusable") == true, "the click focused the view")
    }

    @Test("A spatial tap inside .focusable() is given the click's cell")
    func spatialTapInside() {
        var location: CGPoint?
        let app = TestApp(width: 40, height: 12) {
            Rectangle().fill(.blue)
                .onTapGesture { location = $0 }
                .focusable()
        }
        app.click(at: CellPoint(x: 7, y: 3))
        app.advance(by: .seconds(1))
        #expect(location == CGPoint(x: 7, y: 3))
    }

    @Test("onContinuousHover inside .focusable() hears the pointer")
    func hoverInside() {
        let heard = Heard()
        let app = TestApp(width: 40, height: 12) {
            Rectangle().fill(.blue)
                .onContinuousHover { phase in
                    if case .active = phase { heard.events.append("active") } else { heard.events.append("ended") }
                }
                .focusable()
        }
        app.hover(at: CellPoint(x: 12, y: 6))
        #expect(heard.events == ["active"])
    }

    @Test("onMouseEvent inside .focusable() hears the left press and the pointer coming in")
    func mouseEventInside() {
        let heard = Heard()
        let app = TestApp(width: 40, height: 12) {
            Rectangle().fill(.blue)
                .onMouseEvent { event in
                    switch event.phase {
                    case .pressed: heard.events.append("pressed")
                    case .entered: heard.events.append("entered")
                    default: break
                    }
                    return event.phase == .pressed
                }
                .focusable()
                // Asks the terminal for the pointer's moves, which a raw
                // handler alone does not.
                .onHover { _ in }
        }
        app.hover(at: CellPoint(x: 12, y: 6))
        app.click(at: CellPoint(x: 12, y: 6))
        #expect(heard.events == ["entered", "pressed"])
        #expect(app.focusedID?.hasPrefix("focusable") == true, "the click focused the view")
    }

    @Test("A help inside .focusable() shows under the pointer")
    func helpUnderPointer() {
        let app = TestApp(width: 40, height: 12) {
            VStack {
                Button("first") {}
                Rectangle().fill(.blue).help("TIP").focusable()
            }
        }
        app.hover(at: CellPoint(x: 20, y: 8))
        app.advance(by: .seconds(3))
        #expect(app.screen.contains("TIP"))
    }

    @Test("A button inside .focusable() keeps its click, and the view around it doesn't take the focus")
    func buttonInside() {
        let heard = Heard()
        let app = TestApp(width: 40, height: 6) {
            VStack {
                Button("first") {}
                Button("inner") { heard.events.append("inner") }.focusable()
            }
        }
        // `.focusable()` around a control takes the control's own stop into its
        // subtree, and adds one of its own: the first Tab stop is the button
        // above, which keeps the focus.
        _ = app.screen
        let before = app.focusedID
        #expect(before?.hasPrefix("button") == true, "the first button has the focus")
        try? app.click("inner")
        #expect(heard.events == ["inner"])
        // The button takes the focus, as a click on one does in TUI; the
        // view's click-to-focus stands aside for it.
        #expect(app.focusedID != before)
        #expect(app.focusedID?.hasPrefix("button") == true, "the click was the button's: \(app.focusedID ?? "nothing")")
    }

    @Test("A click on .focusable() text in a scroll view focuses the text, not the scroll view")
    func inScrollView() {
        let app = TestApp(width: 40, height: 6) {
            ScrollView {
                VStack(alignment: .leading) {
                    Button("first") {}
                    Text(verbatim: "plain text").focusable()
                }
            }
        }
        try? app.click("plain text")
        #expect(app.focusedID?.hasPrefix("focusable") == true, "focused: \(app.focusedID ?? "nothing")")
    }

    @Test("A drag that starts on a focusable view focuses it, as a press does")
    func pressFocuses() {
        let app = TestApp(width: 40, height: 12) {
            VStack {
                Button("first") {}
                Rectangle().fill(.blue).focusable()
            }
        }
        app.drag(from: CellPoint(x: 20, y: 8), to: CellPoint(x: 1, y: 0))
        #expect(app.focusedID?.hasPrefix("focusable") == true, "focused: \(app.focusedID ?? "nothing")")
    }
}
